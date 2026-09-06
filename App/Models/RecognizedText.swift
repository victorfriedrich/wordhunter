import Foundation
import CoreGraphics

/// A recognized text item with transcript and normalized bounds.
struct RecognizedText: Identifiable, Sendable {
    let id = UUID()
    let transcript: String
    let normalizedBounds: CGRect  // Normalized 0...1 relative to scanner view
}
