import Foundation

/// Ranks candidates by assigning a score to each.
protocol CandidateRanker {
    func rank(_ candidates: [ScanCandidate]) -> [ScanCandidate]
}

/// Ranks OCR candidates for display.
///
/// In a photo the visually prominent words (large signs,
/// headings, product names) are the ones the user most likely cares about.
/// Bounding-box area is the best proxy for visual prominence. We sqrt-compress
/// the area so that genuinely large text sorts above small text, but extreme
/// differences (e.g. a full-width banner vs. a half-width heading) don't create
/// winner-take-all cliffs. A small penalty for very short words ( less than 3 chars)
/// deranks articles, prepositions, and OCR fragments that rarely make useful
/// vocabulary items.
struct OCRRanker: CandidateRanker {
    func rank(_ candidates: [ScanCandidate]) -> [ScanCandidate] {
        var ranked = candidates
        for i in ranked.indices {
            let area = ranked[i].bounds.map { Double($0.width * $0.height) } ?? 0.0
            var score = sqrt(area)

            // Small penalty for very short words (articles, prepositions, OCR fragments)
            if ranked[i].lemma.count <= 3 {
                score *= 0.8
            }

            ranked[i].rankScore = score
        }
        return ranked.sorted { $0.rankScore > $1.rankScore }
    }
}
