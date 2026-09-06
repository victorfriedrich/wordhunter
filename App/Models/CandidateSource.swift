import Foundation

enum CandidateSource: String, Codable, Hashable {
    case ocr
    case classification
    case context
    
    var displayName: String {
        switch self {
        case .ocr: return "Text"
        case .classification: return "Image"
        case .context: return "Context"
        }
    }
}
