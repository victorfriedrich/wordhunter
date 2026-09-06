import Foundation

protocol TokenNormalizing {
    func normalize(_ raw: String) -> String
}

struct DefaultTokenNormalizer: TokenNormalizing {
    func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lower = trimmed.lowercased()

        let filteredScalars = lower.unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }

        return String(String.UnicodeScalarView(filteredScalars))
    }
}
