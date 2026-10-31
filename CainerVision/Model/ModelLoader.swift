import CoreText
import Foundation
import RealityKit
import simd
import UIKit

/// Turns a library item into a RealityKit entity. The entity is not yet wrapped for gestures.
enum ModelLoader {
    static func loadVisual(for item: AssetItem, libraryRoot: URL) async throws -> Entity {
        switch item.source {
        case .primitive(let spec):
            return try primitive(spec)
        case .text(let spec):
            return try text(spec)
        case .file(let path, let format):
            let url = libraryRoot.appendingPathComponent(path)
            switch format {
            case .usdz, .reality:
                return try loadUSD(at: url, name: item.name)
            case .obj:
                return try await loadOBJ(at: url, name: item.name)
            }
        }
    }

    static func primitive(_ spec: PrimitiveSpec) throws -> Entity {
        let size = max(spec.size, 0.02)
        let mesh: MeshResource
        switch spec.shape {
        case .box:
            mesh = MeshResource.generateBox(size: size, cornerRadius: size * 0.06)
        case .sphere:
            mesh = MeshResource.generateSphere(radius: size * 0.5)
        case .cylinder:
            mesh = MeshResource.generateCylinder(height: size, radius: size * 0.34)
        case .cone:
            mesh = MeshResource.generateCone(height: size, radius: size * 0.42)
        case .capsule:
            mesh = MeshResource.generateCapsule(height: size * 0.55, radius: size * 0.22)
        case .slab:
            mesh = MeshResource.generateBox(width: size * 2.4, height: size * 0.1, depth: size * 1.5)
        case .torus:
            mesh = try ProceduralMesh.torus(meanRadius: size * 0.42, tubeRadius: size * 0.11)
        }
        let material = pbr(color: ColorHex.uiColor(spec.hex), roughness: spec.roughness, metallic: spec.metallic, texture: nil)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    static func text(_ spec: TextSpec) throws -> Entity {
        let string = spec.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else {
            throw UserFacingError(message: "Type a word or two to make 3D text.")
        }
        let mesh = MeshResource.generateText(
            String(string.prefix(24)),
            extrusionDepth: min(max(spec.extrusion, 0.001), 0.04),
            font: spec.font.font(size: 0.08),
            containerFrame: .zero,
            alignment: CTTextAlignment.center,
            lineBreakMode: CTLineBreakMode.byTruncatingTail
        )
        let material = pbr(color: ColorHex.uiColor(spec.hex), roughness: spec.roughness, metallic: spec.metallic, texture: nil)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        let bounds = entity.visualBounds(relativeTo: entity)
        guard bounds.extents.x > 0.0001, bounds.extents.y > 0.0001 else {
            throw UserFacingError(message: "That text couldn't be turned into a 3D model. Try different characters.")
        }
        return entity
    }

    private static func loadUSD(at url: URL, name: String) throws -> Entity {
        do {
            return try Entity.load(contentsOf: url)
        } catch {
            throw UserFacingError(message: "CainerVision couldn't open \(name). Try a USDZ or Reality file.")
        }
    }

    private static func loadOBJ(at url: URL, name: String) async throws -> Entity {
        let parsed = try OBJParser.parse(objURL: url)
        let directory = url.deletingLastPathComponent()
        var cloud: [SIMD3<Float>] = []
        cloud.reserveCapacity(parsed.parts.reduce(0) { $0 + $1.positions.count })
        for part in parsed.parts { cloud.append(contentsOf: part.positions) }
        let fit = fitTransform(for: cloud)
        let root = Entity()
        root.name = name
        for part in parsed.parts {
            let positions = part.positions.map { fit.apply($0) }
            var descriptor = MeshDescriptor(name: part.name)
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(part.normals)
            if part.uvs.count == positions.count {
                descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(part.uvs)
            }
            descriptor.primitives = .triangles(part.indices)
            let mesh = try MeshResource.generate(from: [descriptor])
            let texture = try await loadTexture(part.diffuseTexturePath, relativeTo: directory)
            let color = UIColor(red: CGFloat(part.diffuse.x), green: CGFloat(part.diffuse.y), blue: CGFloat(part.diffuse.z), alpha: 1)
            let material = pbr(color: color, roughness: texture == nil ? 0.55 : 0.45, metallic: 0, texture: texture)
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }
        return root
    }

    private static func loadTexture(_ relativePath: String?, relativeTo directory: URL) async throws -> TextureResource? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        let direct = directory.appendingPathComponent(relativePath)
        let fallback = directory.appendingPathComponent((relativePath as NSString).lastPathComponent)
        let url = FileManager.default.fileExists(atPath: direct.path) ? direct : fallback
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? await TextureResource(contentsOf: url)
    }

    private struct Fit {
        var center: SIMD3<Float>
        var minY: Float
        var scale: Float

        func apply(_ point: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(
                (point.x - center.x) * scale,
                (point.y - minY) * scale,
                (point.z - center.z) * scale
            )
        }
    }

    /// Scales an arbitrary OBJ into a roughly 20 cm object sitting on y = 0.
    private static func fitTransform(for positions: [SIMD3<Float>]) -> Fit {
        guard var minPoint = positions.first, var maxPoint = positions.first else {
            return Fit(center: .zero, minY: 0, scale: 1)
        }
        for point in positions {
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
        }
        let extent = maxPoint - minPoint
        let largest = max(extent.x, max(extent.y, extent.z))
        let scale: Float = largest > 0.000001 ? 0.2 / largest : 1
        let center = (minPoint + maxPoint) * 0.5
        return Fit(center: center, minY: minPoint.y, scale: scale)
    }

    private static func pbr(
        color: UIColor,
        roughness: Float,
        metallic: Float,
        texture: TextureResource?
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let texture {
            material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: .white, texture: .init(texture))
        } else {
            material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color)
        }
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: min(max(roughness, 0), 1))
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: min(max(metallic, 0), 1))
        return material
    }
}
