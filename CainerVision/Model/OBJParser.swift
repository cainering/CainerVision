import Foundation
import simd

/// A triangle mesh parsed from a Wavefront OBJ file, expanded so every corner has its own vertex.
struct OBJMeshData {
    var name: String
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var uvs: [SIMD2<Float>]
    var indices: [UInt32]
    var diffuse: SIMD3<Float>
    var diffuseTexturePath: String?
}

struct OBJParseResult {
    var objectName: String
    var parts: [OBJMeshData]
}

enum OBJParser {
    private static let maxTriangles = 1_500_000

    static func parse(objURL: URL) throws -> OBJParseResult {
        let values = try objURL.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > 80_000_000 {
            throw UserFacingError(message: "That OBJ file is too large for this phone to import.")
        }
        let text: String
        do {
            text = try String(contentsOf: objURL, encoding: .utf8)
        } catch {
            text = try String(contentsOf: objURL, encoding: .isoLatin1)
        }
        if text.utf8.contains(0) {
            throw UserFacingError(message: "That file doesn't look like an OBJ model.")
        }

        let materials = loadMaterials(referencedBy: text, objURL: objURL)
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var objectName = objURL.deletingPathExtension().lastPathComponent
        var currentMaterial = ""
        var buckets: [String: Bucket] = [:]

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let keyword = parts.first else { continue }
            let args = Array(parts.dropFirst())
            switch keyword {
            case "o" where !args.isEmpty && objectName == objURL.deletingPathExtension().lastPathComponent:
                objectName = args.joined(separator: " ")
            case "v":
                guard args.count >= 3, let x = Float(args[0]), let y = Float(args[1]), let z = Float(args[2]) else { continue }
                positions.append(SIMD3(x, y, z))
            case "vn":
                guard args.count >= 3, let x = Float(args[0]), let y = Float(args[1]), let z = Float(args[2]) else { continue }
                normals.append(SIMD3(x, y, z))
            case "vt":
                guard args.count >= 2, let u = Float(args[0]), let v = Float(args[1]) else { continue }
                uvs.append(SIMD2(u, v))
            case "usemtl":
                currentMaterial = args.joined(separator: " ")
            case "f":
                try appendFace(args, positions: positions, normals: normals, uvs: uvs, material: currentMaterial, buckets: &buckets)
            default:
                break
            }
        }

        let ordered = buckets.keys.sorted()
        guard !ordered.isEmpty else {
            throw UserFacingError(message: "That OBJ file doesn't contain any faces.")
        }
        var parts: [OBJMeshData] = []
        var triangleCount = 0
        for key in ordered {
            guard let bucket = buckets[key] else { continue }
            triangleCount += bucket.corners.count / 3
            if triangleCount > maxTriangles {
                throw UserFacingError(message: "That OBJ has too many triangles for this phone.")
            }
            let material = materials[key] ?? MTLMaterial()
            var meshNormals = bucket.normals
            if meshNormals.contains(where: { $0 == nil }) || meshNormals.isEmpty {
                meshNormals = computedNormals(positions: bucket.positions)
            }
            let flatNormals: [SIMD3<Float>] = meshNormals.map { value in
                guard let value else { return SIMD3<Float>(0, 1, 0) }
                let length = simd_length(value)
                return length > 0.00001 ? value / length : SIMD3<Float>(0, 1, 0)
            }
            let hasUV = bucket.uvs.allSatisfy { $0 != nil } && !bucket.uvs.isEmpty
            parts.append(
                OBJMeshData(
                    name: key.isEmpty ? objectName : key,
                    positions: bucket.positions,
                    normals: flatNormals,
                    uvs: hasUV ? bucket.uvs.compactMap { $0 } : [],
                    indices: Array(0..<UInt32(bucket.positions.count)),
                    diffuse: material.diffuse,
                    diffuseTexturePath: material.diffuseMap
                )
            )
        }
        return OBJParseResult(objectName: objectName, parts: parts)
    }

    private struct Bucket {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>?] = []
        var uvs: [SIMD2<Float>?] = []
        var corners: [Int] = []
    }

    private struct MTLMaterial {
        var diffuse = SIMD3<Float>(0.78, 0.76, 0.72)
        var diffuseMap: String?
    }

    private static func appendFace(
        _ tokens: [String],
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        uvs: [SIMD2<Float>],
        material: String,
        buckets: inout [String: Bucket]
    ) throws {
        guard tokens.count >= 3 else { return }
        var corners: [(SIMD3<Float>, SIMD3<Float>?, SIMD2<Float>?)] = []
        for token in tokens {
            guard let corner = resolve(token, positions: positions, normals: normals, uvs: uvs) else {
                throw UserFacingError(message: "That OBJ file has a face this app couldn't read.")
            }
            corners.append(corner)
        }
        var bucket = buckets[material] ?? Bucket()
        if bucket.positions.count > maxTriangles * 3 {
            throw UserFacingError(message: "That OBJ has too many triangles for this phone.")
        }
        for index in 1..<(corners.count - 1) {
            for corner in [corners[0], corners[index], corners[index + 1]] {
                bucket.positions.append(corner.0)
                bucket.normals.append(corner.1)
                bucket.uvs.append(corner.2)
                bucket.corners.append(bucket.positions.count - 1)
            }
        }
        buckets[material] = bucket
    }

    private static func resolve(
        _ token: String,
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        uvs: [SIMD2<Float>]
    ) -> (SIMD3<Float>, SIMD3<Float>?, SIMD2<Float>?)? {
        let pieces = token.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let position = lookup(pieces.first ?? "", count: positions.count).flatMap({ positions[$0] }) else {
            return nil
        }
        let uv: SIMD2<Float>?
        if pieces.count > 1, !pieces[1].isEmpty {
            uv = lookup(pieces[1], count: uvs.count).map { uvs[$0] }
        } else {
            uv = nil
        }
        let normal: SIMD3<Float>?
        if pieces.count > 2, !pieces[2].isEmpty {
            normal = lookup(pieces[2], count: normals.count).map { normals[$0] }
        } else {
            normal = nil
        }
        return (position, normal, uv)
    }

    private static func lookup(_ raw: String, count: Int) -> Int? {
        guard let value = Int(raw), value != 0, count > 0 else { return nil }
        let index = value > 0 ? value - 1 : count + value
        guard index >= 0, index < count else { return nil }
        return index
    }

    private static func computedNormals(positions: [SIMD3<Float>]) -> [SIMD3<Float>?] {
        var accumulated = Array(repeating: SIMD3<Float>.zero, count: positions.count)
        var index = 0
        while index + 2 < positions.count {
            let edge1 = positions[index + 1] - positions[index]
            let edge2 = positions[index + 2] - positions[index]
            let face = simd_cross(edge1, edge2)
            accumulated[index] += face
            accumulated[index + 1] += face
            accumulated[index + 2] += face
            index += 3
        }
        return accumulated.map { $0 as SIMD3<Float>? }
    }

    private static func loadMaterials(referencedBy text: String, objURL: URL) -> [String: MTLMaterial] {
        var libraryNames: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("mtllib") else { continue }
            let name = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { libraryNames.append(name) }
        }
        var materials: [String: MTLMaterial] = [:]
        let directory = objURL.deletingLastPathComponent()
        for name in libraryNames {
            let url = directory.appendingPathComponent(name)
            guard let contents = readText(at: url) else { continue }
            materials.merge(parseMTL(contents), uniquingKeysWith: { _, new in new })
        }
        return materials
    }

    /// MTL libraries and texture images an OBJ points at, relative to the OBJ's folder.
    static func auxiliaryRelativePaths(objURL: URL) -> [String] {
        guard let text = readText(at: objURL) else { return [] }
        var paths: [String] = []
        let directory = objURL.deletingLastPathComponent()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("mtllib") else { continue }
            let name = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }
            paths.append(name)
            let mtlURL = directory.appendingPathComponent(name)
            guard let mtl = readText(at: mtlURL) else { continue }
            for material in parseMTL(mtl).values {
                if let map = material.diffuseMap, !map.isEmpty {
                    paths.append(map)
                }
            }
        }
        return paths
    }

    private static func readText(at url: URL) -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        return try? String(contentsOf: url, encoding: .isoLatin1)
    }

    private static func parseMTL(_ text: String) -> [String: MTLMaterial] {
        var materials: [String: MTLMaterial] = [:]
        var currentName = ""
        var current = MTLMaterial()
        func commit() {
            guard !currentName.isEmpty else { return }
            materials[currentName] = current
        }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let keyword = parts.first else { continue }
            let args = Array(parts.dropFirst())
            switch keyword {
            case "newmtl":
                commit()
                currentName = args.joined(separator: " ")
                current = MTLMaterial()
            case "Kd":
                if args.count >= 3, let r = Float(args[0]), let g = Float(args[1]), let b = Float(args[2]) {
                    current.diffuse = SIMD3(r, g, b)
                }
            case "map_Kd":
                current.diffuseMap = mapPath(from: args)
            default:
                break
            }
        }
        commit()
        return materials
    }

    private static func mapPath(from tokens: [String]) -> String? {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "tga", "webp"]
        if let quoted = tokens.joined(separator: " ").split(separator: "\"").dropFirst().first {
            let path = String(quoted)
            if !path.isEmpty { return path }
        }
        if let match = tokens.last(where: { token in
            let ext = URL(fileURLWithPath: token).pathExtension.lowercased()
            return imageExtensions.contains(ext)
        }) {
            return match
        }
        return tokens.last(where: { !$0.hasPrefix("-") })
    }
}
