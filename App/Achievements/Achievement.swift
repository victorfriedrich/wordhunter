import Foundation
import UIKit

// MARK: - Achievement Identifier

enum AchievementId: String, Codable, CaseIterable, Sendable {
    case theBeginning
    case wordsWordsWords
    case smallTalk
    case palindromeHunter
    case alphabetSoup
    case theSumOfItsParts
    case earlyBird
    case onFire
    case touchGrass
    case whatCameFirst
    case chasingRainbows
    case lightningInABottle
    case whatItSaysOnTheTin
    case aboveTheClouds
    case dejaVu
    case generalist
    case specialist
}

// MARK: - Scan Context

/// Everything a checker might need, precomputed once per save.
struct ScanContext: Sendable {
    let captureId: UUID
    let timestamp: Date
    let location: CapturedLocation?
    
    // Precomputed from candidates
    let lemmas: Set<String>
    let classificationLemmas: Set<String>
    let ocrLemmas: Set<String>
    let shortestLength: Int
    let hour: Int
    
    /// English Vision labels for classification candidates (from `originLabel`).
    let classificationOriginLabels: Set<String>
    
    // Historical
    let totalWordCount: Int
    let allCollectedLemmas: Set<String>
    
    // Streak
    let consecutiveScanDays: Int
    
    // Category progress
    let categoryProgress: [(collected: Int, total: Int)]
    
    // Per-word location history (only populated when Déjà Vu is still locked)
    let wordLocations: [String: [CapturedLocation]]
    
    init(
        candidates: [ScanCandidate],
        captureId: UUID,
        timestamp: Date,
        location: CapturedLocation?,
        totalWordCount: Int,
        allCollectedLemmas: Set<String>,
        consecutiveScanDays: Int = 0,
        categoryProgress: [(collected: Int, total: Int)] = [],
        wordLocations: [String: [CapturedLocation]] = [:]
    ) {
        self.captureId = captureId
        self.timestamp = timestamp
        self.location = location
        self.totalWordCount = totalWordCount
        self.allCollectedLemmas = allCollectedLemmas
        self.consecutiveScanDays = consecutiveScanDays
        self.categoryProgress = categoryProgress
        self.wordLocations = wordLocations
        
        var all = Set<String>()
        var classification = Set<String>()
        var classificationOrigin = Set<String>()
        var ocr = Set<String>()
        var shortest = Int.max
        
        for c in candidates {
            let lower = c.lemma.lowercased()
            all.insert(lower)
            shortest = min(shortest, lower.count)
            
            switch c.source {
            case .classification:
                classification.insert(lower)
                if let origin = c.originLabel?.lowercased() {
                    classificationOrigin.insert(origin)
                }
            case .ocr:
                ocr.insert(lower)
            case .context:
                // Context words are image-derived; count them alongside classification
                // for achievement purposes (they originate from the same scene analysis).
                classification.insert(lower)
            }
        }
        
        self.lemmas = all
        self.classificationLemmas = classification
        self.classificationOriginLabels = classificationOrigin
        self.ocrLemmas = ocr
        self.shortestLength = shortest == Int.max ? 0 : shortest
        self.hour = Calendar.current.component(.hour, from: timestamp)
    }
}

// MARK: - Achievement Definition

struct Achievement: Sendable {
    let id: AchievementId
    let name: String
    let description: String
    let imageName: String
    let requiresLocation: Bool
    let check: @Sendable (ScanContext) -> Bool
}

// MARK: - Achievement Unlock

struct AchievementUnlock {
    let achievement: Achievement
    let captureImage: UIImage
}
