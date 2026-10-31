import Foundation
import UIKit

enum PrimitiveShape: String, Codable, CaseIterable, Identifiable {
    case box
    case sphere
    case cylinder
    case cone
    case torus
    case capsule
    case slab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .box: return "Cube"
        case .sphere: return "Sphere"
        case .cylinder: return "Cylinder"
        case .cone: return "Cone"
        case .torus: return "Ring"
        case .capsule: return "Capsule"
        case .slab: return "Slab"
        }
    }

    var symbolName: String {
        switch self {
        case .box: return "cube.fill"
        case .sphere: return "circle.fill"
        case .cylinder: return "cylinder.fill"
        case .cone: return "cone.fill"
        case .torus: return "circle.circle"
        case .capsule: return "capsule.fill"
        case .slab: return "rectangle.fill"
        }
    }
}

enum TextFontChoice: String, Codable, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Mono"
        }
    }

    func font(size: CGFloat) -> UIFont {
        let weight: UIFont.Weight
        let design: UIFontDescriptor.SystemDesign
        switch self {
        case .system:
            weight = .bold
            design = .default
        case .rounded:
            weight = .bold
            design = .rounded
        case .serif:
            weight = .semibold
            design = .serif
        case .mono:
            weight = .medium
            design = .monospaced
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

enum ImportFormat: String, Codable {
    case usdz
    case reality
    case obj
}

struct PrimitiveSpec: Codable, Equatable {
    var shape: PrimitiveShape
    var hex: String
    var roughness: Float
    var metallic: Float
    /// Characteristic size in meters.
    var size: Float
}

struct TextSpec: Codable, Equatable {
    var string: String
    var hex: String
    var extrusion: Float
    var roughness: Float
    var metallic: Float
    var font: TextFontChoice
}

enum AssetSource: Codable, Equatable {
    case file(path: String, format: ImportFormat)
    case primitive(PrimitiveSpec)
    case text(TextSpec)
}

struct AssetItem: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var order: Int
    var builtIn: Bool
    var source: AssetSource

    var symbolName: String {
        switch source {
        case .primitive(let spec):
            return spec.shape.symbolName
        case .text:
            return "textformat"
        case .file(_, let format):
            return format == .obj ? "square.stack.3d.up" : "shippingbox.fill"
        }
    }
}

struct PlacedInstance: Identifiable, Equatable {
    var id: UUID
    var assetID: UUID
    var title: String
    var hasAnimation: Bool
    var isPlaying: Bool
}

enum ColorHex {
    static func uiColor(_ hex: String) -> UIColor {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            return UIColor(white: 0.8, alpha: 1)
        }
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }

    static func hex(from color: UIColor) -> String {
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "E8E2D8"
        }
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
