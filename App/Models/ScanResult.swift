import Foundation
import UIKit

/// A raw classification hit from Vision, before filtering/translation
struct RawClassificationHit: Sendable {
    let label: String
    let confidence: Float
}

/// Raw output from the scan pipeline.
struct ScanResult {
    let captureId: UUID
    let captureImage: UIImage
    let classificationCandidates: [ScanCandidate]
    let ocrCandidates: [ScanCandidate]
    let unresolvedTokens: [String]
    
    /// All raw classification hits from Vision (before filtering/translation)
    /// Used for debugging and analysis
    let rawClassifications: [RawClassificationHit]
}

/// A section of candidates for display.
struct CandidateSection: Identifiable {
    let id: String
    let title: String
    let candidates: [ScanCandidate]
    let defaultVisibleCount: Int
    
    var visibleCandidates: [ScanCandidate] {
        Array(candidates.prefix(defaultVisibleCount))
    }
    
    var hasMore: Bool {
        candidates.count > defaultVisibleCount
    }
    
    var hiddenCount: Int {
        max(0, candidates.count - defaultVisibleCount)
    }
}

/// Presentation model for the scan results screen.
struct ScanResultPresentation {
    let captureId: UUID
    let captureImage: UIImage
    
    var classificationSection: CandidateSection?
    var ocrSection: CandidateSection?
    var contextSection: CandidateSection?
    
    var selectedIds: Set<String>
    let unresolvedCount: Int
    
    /// Whether the main scan processing is still in progress
    var isProcessing: Bool
    
    /// Whether the contextual suggestions are still loading (shown as shimmer)
    var isContextLoading: Bool
    
    /// Raw classification hits for logging (carried through from ScanResult)
    var rawClassifications: [RawClassificationHit]
    
    var hasAnyResults: Bool {
        (classificationSection?.candidates.isEmpty == false) ||
        (ocrSection?.candidates.isEmpty == false) ||
        (contextSection?.candidates.isEmpty == false)
    }
    
    /// Returns all selected candidates from all sections.
    var selectedCandidates: [ScanCandidate] {
        let all = (classificationSection?.candidates ?? [])
            + (ocrSection?.candidates ?? [])
            + (contextSection?.candidates ?? [])
        return all.filter { selectedIds.contains($0.id) }
    }
    
    /// Creates an initial presentation with just the image (processing state)
    static func processing(captureId: UUID, captureImage: UIImage) -> ScanResultPresentation {
        ScanResultPresentation(
            captureId: captureId,
            captureImage: captureImage,
            classificationSection: nil,
            ocrSection: nil,
            contextSection: nil,
            selectedIds: [],
            unresolvedCount: 0,
            isProcessing: true,
            isContextLoading: false,
            rawClassifications: []
        )
    }
}
