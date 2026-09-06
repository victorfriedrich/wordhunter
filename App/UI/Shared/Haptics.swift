import SwiftUI

/// Haptic trigger values for use with `.sensoryFeedback()`.
/// Attach to views: `.sensoryFeedback(.impact(flexibility: .soft), trigger: hapticTrigger)`
///
/// For imperative contexts where a view modifier isn't practical (e.g., inside a store),
/// use the static methods below.
enum Haptics {
    @MainActor static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @MainActor static func mediumImpact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @MainActor static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
