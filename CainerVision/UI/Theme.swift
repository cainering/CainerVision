import SwiftUI
import UIKit

enum Theme {
    static let background = Color(red: 0.07, green: 0.06, blue: 0.055)
    static let copper = Color(red: 0.89, green: 0.60, blue: 0.29)
    static let ivory = Color(red: 0.96, green: 0.93, blue: 0.88)
    static let record = Color(red: 0.94, green: 0.28, blue: 0.24)
    static let muted = Color.white.opacity(0.62)
}

enum Haptics {
    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func place() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func record() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
