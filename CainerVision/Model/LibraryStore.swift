import Foundation
import QuickLookThumbnailing
import UIKit

/// The on-device catalog of built-in, created, imported, and scanned models.
@Observable
final class LibraryStore {
    private(set) var items: [AssetItem] = []
    private(set) var root: URL?
    private let thumbnails = NSCache<NSString, UIImage>()

    var sortedItems: [AssetItem] {
        items.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func load() throws {
        let root = try Self.makeRoot()
        self.root = root
        let catalog = root.appendingPathComponent("library.json")
        if FileManager.default.fileExists(atPath: catalog.path),
           let data = try? Data(contentsOf: catalog),
           let file = try? JSONDecoder().decode(LibraryFile.self, from: data) {
            items = file.items
        } else {
            try? FileManager.default.removeItem(at: catalog)
            try seedBuiltIns(into: root, replacing: false)
        }
    }

    func addPrimitive(_ spec: PrimitiveSpec, name: String) throws -> AssetItem {
        let item = AssetItem(
            id: UUID(),
            name: uniqueName(name),
            createdAt: Date(),
            order: nextUserOrder(),
            builtIn: false,
            source: .primitive(spec)
        )
        items.append(item)
        try save()
        return item
    }

    func addText(_ spec: TextSpec, name: String) throws -> AssetItem {
        let item = AssetItem(
            id: UUID(),
            name: uniqueName(name),
            createdAt: Date(),
            order: nextUserOrder(),
            builtIn: false,
            source: .text(spec)
        )
        items.append(item)
        try save()
        return item
    }

    func importFile(from url: URL) async throws -> AssetItem {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        guard ["usdz", "reality", "obj", "usd", "usda", "usdc"].contains(ext) else {
            throw UserFacingError(message: "Use a USDZ, Reality, USD, or OBJ file.")
        }
        let root = try existingRoot()
        let folder = root.appendingPathComponent("Assets/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let stored = try copyImport(url, extension: ext, into: folder)
            let format: ImportFormat = ext == "obj" ? .obj : (ext == "reality" ? .reality : .usdz)
            let relative = "Assets/\(folder.lastPathComponent)/\(stored.lastPathComponent)"
            let item = AssetItem(
                id: UUID(),
                name: uniqueName(url.deletingPathExtension().lastPathComponent),
                createdAt: Date(),
                order: nextUserOrder(),
                builtIn: false,
                source: .file(path: relative, format: format)
            )
            _ = try await ModelLoader.loadVisual(for: item, libraryRoot: root)
            items.append(item)
            try save()
            return item
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func addScan(at url: URL, name: String) throws -> AssetItem {
        let root = try existingRoot()
        let folder = root.appendingPathComponent("Assets/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("Scan.usdz")
        try FileManager.default.copyItem(at: url, to: destination)
        let relative = "Assets/\(folder.lastPathComponent)/Scan.usdz"
        let item = AssetItem(
            id: UUID(),
            name: uniqueName(name),
            createdAt: Date(),
            order: nextUserOrder(),
            builtIn: false,
            source: .file(path: relative, format: .usdz)
        )
        items.append(item)
        try save()
        return item
    }

    func delete(_ item: AssetItem) throws {
        if case .file(let path, _) = item.source, let root {
            let file = root.appendingPathComponent(path)
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
        items.removeAll { $0.id == item.id }
        thumbnails.removeObject(forKey: item.id.uuidString as NSString)
        try save()
    }

    func restoreBuiltIns() throws {
        let root = try existingRoot()
        try seedBuiltIns(into: root, replacing: false)
    }

    func thumbnail(for item: AssetItem) async -> UIImage? {
        let key = item.id.uuidString as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard case .file(let path, _) = item.source, let root else { return nil }
        let url = root.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 200, height: 200),
            scale: 2,
            representationTypes: .all
        )
        guard let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage else {
            return nil
        }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    func fileURL(for item: AssetItem) -> URL? {
        guard case .file(let path, _) = item.source, let root else { return nil }
        return root.appendingPathComponent(path)
    }

    private func copyImport(_ url: URL, extension ext: String, into folder: URL) throws -> URL {
        if ext == "usd" || ext == "usda" || ext == "usdc" {
            let data = try Data(contentsOf: url)
            let packed = try USDZPacker.pack(
                named: USDZPacker.internalName(for: data, pathExtension: ext),
                data: data
            )
            let destination = folder.appendingPathComponent("model.usdz")
            try packed.write(to: destination, options: .atomic)
            return destination
        }

        let destination = folder.appendingPathComponent(sanitizedFileName(url.lastPathComponent))
        try FileManager.default.copyItem(at: url, to: destination)
        if ext == "obj" {
            copyOBJCompanions(of: url, to: folder)
        }
        return destination
    }

    private func copyOBJCompanions(of source: URL, to folder: URL) {
        let sourceDir = source.deletingLastPathComponent()
        for relative in OBJParser.auxiliaryRelativePaths(objURL: source) {
            let from = sourceDir.appendingPathComponent(relative)
            let to = folder.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            try? FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: to.path) {
                try? FileManager.default.copyItem(at: from, to: to)
            }
        }
    }

    private func seedBuiltIns(into root: URL, replacing: Bool) throws {
        if replacing { items.removeAll { $0.builtIn } }
        let existingNames = Set(items.map(\.name))
        var seeded = items
        for template in Self.builtInTemplates where !existingNames.contains(template.name) {
            var item = template
            if case .file = template.source {
                let copied = try copyBundledSample(named: template.name, into: root)
                item.source = .file(path: copied, format: .usdz)
            }
            item.id = UUID()
            item.createdAt = Date()
            seeded.append(item)
        }
        items = seeded
        try save()
    }

    private func copyBundledSample(named name: String, into root: URL) throws -> String {
        let resource = Self.sampleResources[name]
        guard let resource, let source = Bundle.main.url(forResource: resource, withExtension: "usdz") else {
            throw UserFacingError(message: "A built-in sample model is missing from the app.")
        }
        let folder = root.appendingPathComponent("Assets/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("\(resource).usdz")
        try FileManager.default.copyItem(at: source, to: destination)
        return "Assets/\(folder.lastPathComponent)/\(resource).usdz"
    }

    private func save() throws {
        let root = try existingRoot()
        let file = LibraryFile(version: 1, items: items)
        let data = try JSONEncoder().encode(file)
        try data.write(to: root.appendingPathComponent("library.json"), options: .atomic)
    }

    private func existingRoot() throws -> URL {
        if let root { return root }
        let root = try Self.makeRoot()
        self.root = root
        return root
    }

    private func uniqueName(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Object" : cleaned
        let names = Set(items.map(\.name))
        if !names.contains(base) { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    private func nextUserOrder() -> Int {
        max(100, (items.map(\.order).max() ?? 100) + 1)
    }

    private func sanitizedFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-"))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned.isEmpty ? "model" : cleaned
    }

    private static func makeRoot() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("CainerVision", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static let sampleResources = [
        "Warm Cube": "WarmCube",
        "Spinning Token": "SpinningToken",
        "Guide Cone": "GuideCone",
    ]

    private static var builtInTemplates: [AssetItem] {
        let now = Date()
        func primitive(_ name: String, _ shape: PrimitiveShape, _ hex: String, _ rough: Float, _ metal: Float, _ order: Int) -> AssetItem {
            AssetItem(
                id: UUID(),
                name: name,
                createdAt: now,
                order: order,
                builtIn: true,
                source: .primitive(PrimitiveSpec(shape: shape, hex: hex, roughness: rough, metallic: metal, size: 0.1))
            )
        }
        return [
            primitive("Plaster Cube", .box, "E7D3C0", 0.72, 0, 0),
            primitive("Clay Sphere", .sphere, "C47A5A", 0.62, 0, 1),
            primitive("Brass Cylinder", .cylinder, "C6A15A", 0.32, 0.86, 2),
            primitive("Amber Cone", .cone, "E39A4A", 0.4, 0.04, 3),
            primitive("Copper Ring", .torus, "B87333", 0.34, 0.82, 4),
            primitive("Soft Capsule", .capsule, "F3EFE8", 0.5, 0, 5),
            primitive("Stage Slab", .slab, "2C2926", 0.84, 0.02, 6),
            AssetItem(
                id: UUID(),
                name: "Hello",
                createdAt: now,
                order: 7,
                builtIn: true,
                source: .text(TextSpec(string: "Hello", hex: "F4EFE6", extrusion: 0.012, roughness: 0.45, metallic: 0.05, font: .rounded))
            ),
            AssetItem(id: UUID(), name: "Warm Cube", createdAt: now, order: 8, builtIn: true, source: .file(path: "", format: .usdz)),
            AssetItem(id: UUID(), name: "Spinning Token", createdAt: now, order: 9, builtIn: true, source: .file(path: "", format: .usdz)),
            AssetItem(id: UUID(), name: "Guide Cone", createdAt: now, order: 10, builtIn: true, source: .file(path: "", format: .usdz)),
        ]
    }
}

private struct LibraryFile: Codable {
    var version: Int
    var items: [AssetItem]
}
