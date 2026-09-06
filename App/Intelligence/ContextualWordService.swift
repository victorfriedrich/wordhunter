import Foundation
import os.log

#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.app.scan", category: "ContextualWordService")

/// Uses Apple's FoundationModels framework (iOS 26+) to suggest vocabulary
/// in the learner's target language, based on English classification labels.
///
/// Returns words in the target language (e.g. Spanish verbs/adjectives).
/// The caller validates each word against the lexicon and drops unknowns.
///
/// Call the static `suggestWords(fromLabels:existingLabels:language:)` entry point,
/// which handles all platform/availability checks internally.
@MainActor
final class ContextualWordService {

    /// Whether Apple Intelligence contextual suggestions are available on this device.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    /// Entry point for the controller. Handles platform checks internally.
    /// Callers don't need any `#if canImport` or `#available` guards.
    ///
    /// Returns words in the target language suitable for lexicon validation,
    /// or an empty array if the platform doesn't support FoundationModels.
    static func suggestWords(
        fromLabels labels: [String],
        existingLabels: Set<String>,
        language: Language
    ) async -> [String] {
        #if DEBUG
        logger.info("📥 suggestWords called — labels: \(labels, privacy: .public), existingLabels: \(existingLabels.sorted(), privacy: .public), language: \(language.displayName, privacy: .public)")
        #endif

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let service = ContextualWordService()
            return await service.suggest(
                fromLabels: labels,
                existingLabels: existingLabels,
                language: language
            )
        }
        #endif
        return []
    }

    // MARK: - Internal

    #if canImport(FoundationModels)

    @available(iOS 26.0, *)
    private func suggest(
        fromLabels labels: [String],
        existingLabels: Set<String>,
        language: Language
    ) async -> [String] {
        // Normalize existing labels once so exclusion is case-insensitive.
        let normalizedExisting: Set<String> = Set(
            existingLabels.map {
                $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )

        // Normalize and dedupe input labels so we do not feed duplicates like "Dog" and "dog".
        let normalizedInputLabels: [String] = {
            var seen = Set<String>()
            var result: [String] = []
            result.reserveCapacity(labels.count)
            for raw in labels {
                let v = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !v.isEmpty, !seen.contains(v) else { continue }
                seen.insert(v)
                result.append(v)
            }
            return result
        }()

        guard !normalizedInputLabels.isEmpty else { return [] }

        do {
            #if DEBUG
            let totalStart = ContinuousClock.now
            let sessionStart = ContinuousClock.now
            #endif

            let session = LanguageModelSession()

            #if DEBUG
            let sessionMs = Int((ContinuousClock.now - sessionStart).components.attoseconds / 1_000_000_000_000_000)
            #endif

            let prompt = buildPrompt(
                labels: normalizedInputLabels,
                existing: normalizedExisting,
                language: language
            )

            #if DEBUG
            logger.info("📝 Prompt:\n\(prompt, privacy: .public)")
            let respondStart = ContinuousClock.now
            #endif

            let response = try await session.respond(
                to: prompt,
                generating: ContextualLabelsResponse.self
            )

            #if DEBUG
            let respondMs = Int((ContinuousClock.now - respondStart).components.attoseconds / 1_000_000_000_000_000)
            logger.info("🤖 Raw output: \(response.content.labels, privacy: .public)")
            #endif

            // Dedupe and exclude. Iterates in model output order, so ranking is preserved.
            var seen = normalizedExisting
            var out: [String] = []
            out.reserveCapacity(response.content.labels.count)
            for raw in response.content.labels {
                let v = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !v.isEmpty, !seen.contains(v) else { continue }
                seen.insert(v)
                out.append(v)
            }

            #if DEBUG
            let totalMs = Int((ContinuousClock.now - totalStart).components.attoseconds / 1_000_000_000_000_000)
            logger.info("⏱️ session init: \(sessionMs)ms  respond: \(respondMs)ms  total: \(totalMs)ms  →  \(out, privacy: .public)")
            #endif

            return out
        } catch {
            logger.error("❌ FoundationModels error: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    @available(iOS 26.0, *)
    private func buildPrompt(labels: [String], existing: Set<String>, language: Language) -> String {
        let labelList = labels.joined(separator: ", ")
        let excludeList = existing.sorted().joined(separator: ", ")
        let langName = language.displayName

        return """
        I see these objects in a photo: \(labelList). They are ranked by importance.

        Suggest 8-10 single \(langName) VERBS or ADJECTIVES directly related to these objects. Among the objects in the photo, prioritize concrete over abstract words, e.g. in a list of "cat", "animal", "mammal", suggest related words for cat.

        Focus on: what a person would do WITH them, what these things do, how they look or feel

        Examples (the exact words should vary by language):
        - For a dog in English: "bark", "fetch", "soft"
        - For coffee in English: "pour", "hot", "sip"
        - For a dog in Spanish: "ladrar", "suave", "jugar"

        Do NOT suggest more nouns or objects. The most conceptually related words should come first in your answer.
        Return words in \(langName).

        Exclude: \(excludeList).
        """
    }

    #endif
}

// MARK: - Structured Output

#if canImport(FoundationModels)

@available(iOS 26.0, *)
@Generable
struct ContextualLabelsResponse {
    @Guide(description: "Related vocabulary words in the target language")
    @Guide(.count(6...8))
    var labels: [String]
}

#endif
