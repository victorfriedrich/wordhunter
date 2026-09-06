import Foundation

enum Language: String, Codable, CaseIterable, Identifiable, Sendable {
    case english
    case spanish
    case french
    case german

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
            // only needed when more languages are added to the SQL database
        case .french: return "French"
        case .german: return "German"
        }
    }
    
    /// Articles that should be stripped for search and sorting purposes
    var articles: [String] {
        switch self {
            // Not needed right now because of passthrough lexicon
        case .english: return ["the", "a", "an"]
        case .spanish: return ["el", "la", "los", "las", "un", "una", "unos", "unas"]
            
            // only needed when more languages are added to the SQL database
        case .french: return ["le", "la", "les", "l'", "un", "une", "des"]
        case .german: return ["der", "die", "das", "ein", "eine"]
        }
    }
    
    /// Checks whether a word/phrase starts with one of this language's articles.
    /// e.g. "el gato" -> true, "l'homme" -> true, "gato" -> false
    func hasLeadingArticle(in text: String) -> Bool {
        let lowered = text.lowercased()
        for article in articles {
            if article.hasSuffix("'") {
                if lowered.hasPrefix(article) { return true }
            } else {
                if lowered.hasPrefix(article + " ") { return true }
            }
        }
        return false
    }
    
    /// Strips leading article from a word/phrase for this language.
    /// e.g. "el gato" -> "gato", "l'homme" -> "homme", "die Katze" -> "Katze"
    func strippingArticle(from text: String) -> String {
        let lowered = text.lowercased()
        for article in articles {
            if article.hasSuffix("'") {
                // Handle contractions like French "l'"
                if lowered.hasPrefix(article) {
                    return String(text.dropFirst(article.count))
                }
            } else {
                let prefix = article + " "
                if lowered.hasPrefix(prefix) {
                    return String(text.dropFirst(prefix.count))
                }
            }
        }
        return text
    }
}

// MARK: - Diacritic Folding

extension String {
    /// Returns the string with all diacritics/accents removed and lowercased.
    /// "cafÃ©" â†’ "cafe", "Ã¼ber" â†’ "uber", "rÃ©sumÃ©" â†’ "resume"
    /// Used for sorting only â€” NOT for DB search queries (too expensive).
    var foldedForSearch: String {
        self.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
