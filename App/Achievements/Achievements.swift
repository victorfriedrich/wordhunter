import Foundation
import CoreLocation

/// All achievements defined with simple check closures.
enum Achievements {
    
    // MARK: - Milestones
    
    private static let milestones: [Achievement] = [
        Achievement(
            id: .theBeginning,
            name: "The Beginning",
            description: "Collect your very first word",
            imageName: "TheBeginning",
            requiresLocation: false,
            check: { $0.totalWordCount >= 1 }
        ),
        Achievement(
            id: .wordsWordsWords,
            name: "Words, Words, Words",
            description: "Collect 100 unique words",
            imageName: "WordsWordsWords",
            requiresLocation: false,
            check: { $0.totalWordCount >= 100 }
        ),
    ]
    
    // MARK: - Word Properties
    
    private static let wordProperties: [Achievement] = [
        Achievement(
            id: .smallTalk,
            name: "Small Talk",
            description: "Collect a 2-letter word",
            imageName: "SmallTalk",
            requiresLocation: false,
            check: { $0.shortestLength > 0 && $0.shortestLength <= 2 }
        ),
        Achievement(
            id: .palindromeHunter,
            name: "Palindrome Hunter",
            description: "Collect a word that reads the same forwards and backwards",
            imageName: "PalindromeHunter",
            requiresLocation: false,
            check: { ctx in
                ctx.lemmas.contains { $0.count >= 2 && $0 == String($0.reversed()) }
            }
        ),
        Achievement(
            id: .alphabetSoup,
            name: "Alphabet Soup",
            description: "Collect a word starting with every letter of the alphabet",
            imageName: "AlphabetSoup",
            requiresLocation: false,
            check: { ctx in
                let letters = Set(ctx.allCollectedLemmas.compactMap { $0.first })
                return Set("abcdefghijklmnopqrstuvwxyz").isSubset(of: letters)
            }
        ),
        Achievement(
            id: .theSumOfItsParts,
            name: "The Sum of Its Parts",
            description: "Collect both halves of a compound word and the complete word separately",
            imageName: "TheSumOfItsParts",
            requiresLocation: false,
            check: { ctx in
                let all = ctx.allCollectedLemmas
                let newLemmas = ctx.lemmas // words saved in this scan
                
                // Path 1: A new word IS the compound — check if its halves exist.
                // Cost: O(newWords × avgWordLength) with O(1) set lookups per split.
                for word in newLemmas where word.count >= 4 {
                    if isCompoundWithKnownHalves(word, in: all) {
                        return true
                    }
                }
                
                // Path 2: A new word completes a compound as a half.
                // For each new word N and each existing word E, check if
                // N+E or E+N exists in the collection as a compound.
                // Cost: O(newWords × collectionSize) string concatenations
                // + O(1) set lookups — no String.Index manipulation needed.
                for newWord in newLemmas where newWord.count >= 2 {
                    for existing in all where existing.count >= 2 {
                        // newWord is the LEFT half: newWord + existing = compound?
                        let compoundA = newWord + existing
                        if compoundA.count >= 4 && all.contains(compoundA) {
                            return true
                        }
                        // newWord is the RIGHT half: existing + newWord = compound?
                        let compoundB = existing + newWord
                        if compoundB.count >= 4 && all.contains(compoundB) {
                            return true
                        }
                    }
                }
                
                return false
            }
        ),
    ]
    
    /// Check if a word can be split into two halves that both exist in the collection.
    private static func isCompoundWithKnownHalves(_ word: String, in all: Set<String>) -> Bool {
        for i in 2..<(word.count - 1) {
            let splitIndex = word.index(word.startIndex, offsetBy: i)
            let left = String(word[word.startIndex..<splitIndex])
            let right = String(word[splitIndex..<word.endIndex])
            if left.count >= 2 && right.count >= 2
                && all.contains(left) && all.contains(right) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Time-Based
    
    private static let timeBased: [Achievement] = [
        Achievement(
            id: .earlyBird,
            name: "Early Bird",
            description: "Scan a word between 4-6 AM",
            imageName: "EarlyBird",
            requiresLocation: false,
            check: { $0.hour >= 4 && $0.hour < 6 }
        ),
        Achievement(
            id: .onFire,
            name: "On Fire",
            description: "Scan at least one new word for 7 consecutive days",
            imageName: "OnFire",
            requiresLocation: false,
            check: { $0.consecutiveScanDays >= 7 }
        ),
    ]
    
    // MARK: - Classification
    //
    // These checks use `classificationOriginLabels` — the English Vision identifiers
    // (e.g. "hand", "grass") — so they work regardless of the app's target language.
    // In Spanish mode, classificationLemmas would contain "mano"/"hierba" but
    // classificationOriginLabels still contains the English labels from Vision.
    
    private static let classification: [Achievement] = [
        Achievement(
            id: .touchGrass,
            name: "Touch Grass",
            description: "Collect 'hand' and 'grass' in a single image",
            imageName: "TouchGrass",
            requiresLocation: false,
            check: { Set(["hand", "grass"]).isSubset(of: $0.classificationOriginLabels) }
        ),
        Achievement(
            id: .whatCameFirst,
            name: "What Came First?",
            description: "Collect 'chicken' or 'egg'",
            imageName: "WhatCameFirst",
            requiresLocation: false,
            check: { !$0.classificationOriginLabels.isDisjoint(with: ["chicken", "egg"]) }
        ),
        Achievement(
            id: .chasingRainbows,
            name: "Chasing Rainbows",
            description: "Collect 'rainbow' in a picture",
            imageName: "ChasingRainbows",
            requiresLocation: false,
            check: { $0.classificationOriginLabels.contains("rainbow") }
        ),
        Achievement(
            id: .lightningInABottle,
            name: "Lightning in a Bottle",
            description: "Collect 'lightning' or 'thunderstorm' in a picture",
            imageName: "LightningInABottle",
            requiresLocation: false,
            check: { !$0.classificationOriginLabels.isDisjoint(with: ["lightning", "thunderstorm", "thunder"]) }
        ),
    ]
    
    // MARK: - Multi-Source
    
    private static let multiSource: [Achievement] = [
        Achievement(
            id: .whatItSaysOnTheTin,
            name: "What It Says on the Tin",
            description: "Collect a word that appears as both an object and written text in an image",
            imageName: "WhatItSaysOnTheTin",
            requiresLocation: false,
            // Uses classificationLemmas (target-language) since OCR also produces target-language lemmas
            check: { !$0.classificationLemmas.isDisjoint(with: $0.ocrLemmas) }
        ),
    ]
    
    // MARK: - Location
    
    private static let location: [Achievement] = [
        Achievement(
            id: .aboveTheClouds,
            name: "Above the Clouds",
            description: "Scan a word above 1,000 meters elevation",
            imageName: "AboveTheClouds",
            requiresLocation: true,
            check: { ctx in
                guard let loc = ctx.location else { return false }
                return loc.altitude >= 1000 && loc.verticalAccuracy >= 0 && loc.verticalAccuracy <= 50
            }
        ),
        Achievement(
            id: .dejaVu,
            name: "Déjà Vu",
            description: "Scan the same word in 3 locations at least 500 meters apart",
            imageName: "DejaVu",
            requiresLocation: true,
            check: { ctx in
                // Check each word's location history for 3 locations mutually ≥500m apart
                for (_, locations) in ctx.wordLocations {
                    guard locations.count >= 3 else { continue }
                    if hasThreeDistantLocations(locations, minDistance: 500) {
                        return true
                    }
                }
                return false
            }
        ),
    ]
    
    // MARK: - Category
    
    private static let category: [Achievement] = [
        Achievement(
            id: .generalist,
            name: "Generalist",
            description: "Collect at least one word in every category",
            imageName: "JackOfAllTrades",
            requiresLocation: false,
            check: { ctx in
                guard !ctx.categoryProgress.isEmpty else { return false }
                return ctx.categoryProgress.allSatisfy { $0.collected >= 1 }
            }
        ),
        Achievement(
            id: .specialist,
            name: "Specialist",
            description: "Collect every word in a single category",
            imageName: "MasterOfOne",
            requiresLocation: false,
            check: { ctx in
                ctx.categoryProgress.contains { $0.total > 0 && $0.collected >= $0.total }
            }
        ),
    ]
    
    // MARK: - All (ordered)
    
    private static let unorderedAll: [Achievement] =
        milestones + wordProperties + timeBased + classification + multiSource + location + category
    
    private static let unorderedById: [AchievementId: Achievement] = {
        Dictionary(uniqueKeysWithValues: unorderedAll.map { ($0.id, $0) })
    }()
    
    static let all: [Achievement] = {
        // Requested order:
        let orderedIds: [AchievementId] = [
            .theBeginning,
            .wordsWordsWords,
            .alphabetSoup,
            .aboveTheClouds,
            .dejaVu,
            .earlyBird,
            .whatItSaysOnTheTin,
            .palindromeHunter,
            .generalist,
            .specialist,
            .onFire,
            .touchGrass,
            .whatCameFirst,
            .chasingRainbows,
            .lightningInABottle,
            .theSumOfItsParts,
            .smallTalk
        ]
        
        var used = Set<AchievementId>()
        var result: [Achievement] = []
        
        for id in orderedIds {
            if let a = unorderedById[id] {
                result.append(a)
                used.insert(id)
            }
        }
        
        // Append anything not explicitly ordered (eg Palindrome Hunter) to avoid dropping achievements.
        result += unorderedAll.filter { !used.contains($0.id) }
        return result
    }()
    
    static let byId: [AchievementId: Achievement] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()
    
    // MARK: - Helpers
    
    /// Check if a list of locations contains at least 3 that are mutually ≥ minDistance meters apart.
    private static func hasThreeDistantLocations(
        _ locations: [CapturedLocation],
        minDistance: Double
    ) -> Bool {
        let coords = locations.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        
        // Try all combinations of 3
        let n = coords.count
        for i in 0..<n {
            for j in (i + 1)..<n {
                guard coords[i].distance(from: coords[j]) >= minDistance else { continue }
                for k in (j + 1)..<n {
                    if coords[i].distance(from: coords[k]) >= minDistance
                        && coords[j].distance(from: coords[k]) >= minDistance {
                        return true
                    }
                }
            }
        }
        return false
    }
}
