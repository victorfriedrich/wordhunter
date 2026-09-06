import Foundation
import UIKit
import Vision

/// Orchestrates the scan flow: capture → classify → OCR → rank → present
@available(iOS 18.0, *)
@MainActor
final class ScanPipeline {
    private let language: Language
    private let normalizer: TokenNormalizing
    private let lexicon: LexiconResolving
    private let sqliteLexicon: SQLiteLexicon?  // For reverse lookups
    
    private let classificationRanker: CandidateRanker
    private let ocrRanker: CandidateRanker
    private let classificationDisplayStrategy: DisplayStrategy

    
    private static let minClassificationConfidence: Float = 0.15
    
    // MARK: - Initialization
    
    /// Initialize with explicit lexicon (for testing or custom setups)
    init(
        language: Language,
        normalizer: TokenNormalizing,
        lexicon: LexiconResolving,
        sqliteLexicon: SQLiteLexicon? = nil,
        classificationRanker: CandidateRanker? = nil,
        ocrRanker: CandidateRanker = OCRRanker(),
        classificationDisplayStrategy: DisplayStrategy = FixedCountStrategy(count: 3)
    ) {
        self.language = language
        self.normalizer = normalizer
        self.lexicon = lexicon
        self.sqliteLexicon = sqliteLexicon
        self.classificationRanker = classificationRanker ?? DerankedClassificationRanker(language: language)
        self.ocrRanker = ocrRanker
        self.classificationDisplayStrategy = classificationDisplayStrategy
    }
    
    /// Convenience initializer using AppDependencies and AppSettings
    convenience init(settings: AppSettings, deps: AppDependencies) {
        self.init(
            language: settings.sourceLanguage,
            normalizer: deps.normalizer,
            lexicon: deps.lexicon(for: settings),
            sqliteLexicon: deps.lexiconProvider.sqlite
        )
    }
    
    /// Classification-only result for progressive display.
    /// Returns quickly so the UI can show image-based candidates while OCR runs.
    struct ClassificationResult {
        let candidates: [ScanCandidate]
        let rawHits: [RawClassificationHit]
        /// Cached JPEG data + orientation for reuse by OCR, avoiding redundant encoding.
        let imageData: Data?
        let orientation: CGImagePropertyOrientation
    }
    
    /// Prepare JPEG data and orientation from a UIImage once, for reuse across classification and OCR.
    private func prepareImageData(from image: UIImage) -> (data: Data, orientation: CGImagePropertyOrientation)? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return (data, CGImagePropertyOrientation(image.imageOrientation))
    }
    
    /// Run only image classification (no OCR). Used for progressive display
    /// so the UI can show classification candidates while OCR runs in parallel.
    func processClassificationOnly(
        captureImage: UIImage,
        classificationOverrideHits: [(label: String, confidence: Float)] = []
    ) async -> ClassificationResult {
        if classificationOverrideHits.isEmpty {
            guard let prepared = prepareImageData(from: captureImage) else {
                return ClassificationResult(candidates: [], rawHits: [], imageData: nil, orientation: .up)
            }
            let (candidates, rawHits) = await classifyImage(imageData: prepared.data, orientation: prepared.orientation)
            return ClassificationResult(candidates: candidates, rawHits: rawHits, imageData: prepared.data, orientation: prepared.orientation)
        } else {
            let (candidates, rawHits) = buildFromOverrideHits(classificationOverrideHits)
            let prepared = prepareImageData(from: captureImage)
            return ClassificationResult(candidates: candidates, rawHits: rawHits, imageData: prepared?.data, orientation: prepared?.orientation ?? .up)
        }
    }
    
    /// Process a captured image into a scan result.
    /// Runs Vision OCR internally on the capture image with language-appropriate settings.
    ///
    /// - Parameter classificationOverrides: If non-empty, used instead of
    ///   `VNClassifyImageRequest` (which doesn't run on simulator).
    /// - Parameter precomputedClassification: If provided, skips classification
    ///   (reuses result from `processClassificationOnly`). Also reuses cached image data for OCR.
    func process(
        captureId: UUID,
        captureImage: UIImage,
        classificationOverrideHits: [(label: String, confidence: Float)] = [],
        precomputedClassification: ClassificationResult? = nil
    ) async -> ScanResult {
        let classificationCandidates: [ScanCandidate]
        let rawClassifications: [RawClassificationHit]
        let cachedImageData: Data?
        let cachedOrientation: CGImagePropertyOrientation
        
        if let precomputed = precomputedClassification {
            classificationCandidates = precomputed.candidates
            rawClassifications = precomputed.rawHits
            cachedImageData = precomputed.imageData
            cachedOrientation = precomputed.orientation
        } else if classificationOverrideHits.isEmpty {
            let prepared = prepareImageData(from: captureImage)
            if let prepared {
                let result = await classifyImage(imageData: prepared.data, orientation: prepared.orientation)
                classificationCandidates = result.candidates
                rawClassifications = result.rawHits
            } else {
                classificationCandidates = []
                rawClassifications = []
            }
            cachedImageData = prepared?.data
            cachedOrientation = prepared?.orientation ?? .up
        } else {
            (classificationCandidates, rawClassifications) = buildFromOverrideHits(classificationOverrideHits)
            let prepared = prepareImageData(from: captureImage)
            cachedImageData = prepared?.data
            cachedOrientation = prepared?.orientation ?? .up
        }
        
        let ocrTexts: [RecognizedText]
        if let imageData = cachedImageData {
            ocrTexts = await performOCR(imageData: imageData, orientation: cachedOrientation)
        } else {
            ocrTexts = []
        }
        let ocrCandidates: [ScanCandidate]
        let unresolvedTokens: [String]
        (ocrCandidates, unresolvedTokens) = processOCRTexts(ocrTexts)
        
        return ScanResult(
            captureId: captureId,
            captureImage: captureImage,
            classificationCandidates: classificationCandidates,
            ocrCandidates: ocrCandidates,
            unresolvedTokens: unresolvedTokens,
            rawClassifications: rawClassifications
        )
    }
    
    private func buildFromOverrideHits(
        _ hits: [(label: String, confidence: Float)]
    ) -> (candidates: [ScanCandidate], rawHits: [RawClassificationHit]) {
        let sorted = hits.sorted { $0.confidence > $1.confidence }

        let rawHits: [RawClassificationHit] = sorted.prefix(50).map {
            RawClassificationHit(
                label: $0.label.lowercased().replacingOccurrences(of: "_", with: " "),
                confidence: $0.confidence
            )
        }

        let candidates = buildCandidatesFromHits(sorted, source: .classification, excluding: [])
        return (candidates, rawHits)
    }

    private func buildCandidatesFromHits(
        _ hits: [(label: String, confidence: Float)],
        source: CandidateSource,
        excluding existingLemmas: Set<String>
    ) -> [ScanCandidate] {
        let targetLanguage = self.language
        var candidates: [ScanCandidate] = []
        var seenLemmas = existingLemmas

        for hit in hits {
            let cleanLabel = hit.label.lowercased().replacingOccurrences(of: "_", with: " ")

            if targetLanguage == .english {
                guard !seenLemmas.contains(cleanLabel) else { continue }
                seenLemmas.insert(cleanLabel)

                candidates.append(ScanCandidate(
                    language: targetLanguage,
                    lemma: cleanLabel,
                    translation: nil,
                    source: source,
                    bounds: nil,
                    confidence: hit.confidence,
                    originLabel: cleanLabel
                ))
            } else {
                let entries = sqliteLexicon?.lookupByTranslation(cleanLabel, language: targetLanguage) ?? []
                for entry in entries {
                    let lemmaKey = entry.lemma.lowercased()
                    guard !seenLemmas.contains(lemmaKey) else { continue }
                    seenLemmas.insert(lemmaKey)

                    candidates.append(ScanCandidate(
                        language: targetLanguage,
                        lemma: entry.lemma,
                        translation: entry.translation,
                        source: source,
                        bounds: nil,
                        confidence: hit.confidence,
                        originLabel: cleanLabel
                    ))
                }
            }

            if candidates.count >= 10 { break }
        }

        return candidates
    }

    
    /// Build a presentation model from raw scan results.
    func buildPresentation(from result: ScanResult) -> ScanResultPresentation {
        let rankedClassification = classificationRanker.rank(result.classificationCandidates)
        let rankedOCR = ocrRanker.rank(result.ocrCandidates)
        
        let classificationVisibleCount = classificationDisplayStrategy.visibleCount(for: rankedClassification)

        // Build the adaptive OCR display strategy from this scan's data.
        let totalBoundsArea = result.ocrCandidates.reduce(0.0) { sum, c in
            sum + Double(c.bounds.map { $0.width * $0.height } ?? 0)
        }
        let ocrDisplayStrategy = AdaptiveOCRDisplayStrategy(
            classificationLabels: result.rawClassifications.map { $0.label },
            resolvedWordCount: result.ocrCandidates.count,
            totalBoundsArea: totalBoundsArea
        )
        let ocrVisibleCount = ocrDisplayStrategy.visibleCount(for: rankedOCR)
        
        let classificationSection: CandidateSection? = rankedClassification.isEmpty ? nil : CandidateSection(
            id: "classification",
            title: "From Image",
            candidates: rankedClassification,
            defaultVisibleCount: classificationVisibleCount
        )
        
        let ocrSection: CandidateSection? = rankedOCR.isEmpty ? nil : CandidateSection(
            id: "ocr",
            title: "From Text",
            candidates: rankedOCR,
            defaultVisibleCount: ocrVisibleCount
        )
        
        return ScanResultPresentation(
            captureId: result.captureId,
            captureImage: result.captureImage,
            classificationSection: classificationSection,
            ocrSection: ocrSection,
            contextSection: nil,
            selectedIds: [],  // Nothing selected by default
            unresolvedCount: result.unresolvedTokens.count,
            isProcessing: false,
            isContextLoading: false,
            rawClassifications: result.rawClassifications
        )
    }
    
    /// Build context candidates from target-language words suggested by Apple Intelligence.
    /// Each word is validated against the lexicon — words not found are dropped.
    func buildContextSection(
        fromTargetLanguageWords words: [String],
        excluding existingLemmas: Set<String> = []
    ) -> CandidateSection? {
        let lexicon: LexiconResolving = sqliteLexicon ?? PassthroughLexicon()
        
        var candidates: [ScanCandidate] = []
        var seenLemmas = existingLemmas
        
        for (i, word) in words.enumerated() {
            let clean = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            
            let entry = lexicon.resolve(observed: clean, normalized: clean, language: language)
            let key = entry.lemma.lowercased()
            guard !seenLemmas.contains(key) else { continue }
            seenLemmas.insert(key)
            
            candidates.append(ScanCandidate(
                language: language,
                lemma: entry.lemma,
                translation: entry.translation,
                source: .context,
                bounds: nil,
                confidence: max(0.9 - Float(i) * 0.05, 0.2),
                originLabel: clean
            ))
            if candidates.count >= 6 { break }
        }
        
        guard !candidates.isEmpty else { return nil }
        return CandidateSection(
            id: "context",
            title: "From Context",
            candidates: candidates,
            defaultVisibleCount: min(4, candidates.count)
        )
    }
    // MARK: - Image Classification
    
    private struct ClassificationHit: Sendable {
        let identifier: String
        let confidence: Float
    }
    
    /// Returns both the filtered candidates AND the raw classification hits for logging.
    private func classifyImage(imageData: Data, orientation: CGImagePropertyOrientation) async -> (candidates: [ScanCandidate], rawHits: [RawClassificationHit]) {
        let hits = await performClassification(imageData: imageData, orientation: orientation)
        
        // Convert ALL hits to RawClassificationHit for logging (top 50 by confidence)
        let rawHits = hits.prefix(50).map { hit in
            RawClassificationHit(
                label: hit.identifier.lowercased().replacingOccurrences(of: "_", with: " "),
                confidence: hit.confidence
            )
        }
        
        // Filter by confidence and delegate to unified builder
        let filteredHits: [(label: String, confidence: Float)] = hits
            .filter { $0.confidence >= Self.minClassificationConfidence }
            .map { (label: $0.identifier, confidence: $0.confidence) }
        
        let candidates = buildCandidatesFromHits(filteredHits, source: .classification, excluding: [])
        return (candidates, rawHits)
    }
    
    nonisolated private func performClassification(
        imageData: Data,
        orientation: CGImagePropertyOrientation
    ) async -> [ClassificationHit] {
        await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(data: imageData, orientation: orientation, options: [:])
                
                do {
                    try handler.perform([request])
                } catch {
                    return []
                }
                
                let observations = (request.results as? [VNClassificationObservation]) ?? []
                return observations.map { ClassificationHit(identifier: $0.identifier, confidence: $0.confidence) }
            }
        }.value
    }
    
    // MARK: - Vision OCR
    
    /// Runs VNRecognizeTextRequest on pre-encoded image data with language-appropriate settings.
    private func performOCR(imageData: Data, orientation: CGImagePropertyOrientation) async -> [RecognizedText] {
        let recognitionLanguages = language.visionLanguageCodes
        
        let results: [RecognizedText] = await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = recognitionLanguages
                
                let handler = VNImageRequestHandler(
                    data: imageData,
                    orientation: orientation,
                    options: [:]
                )
                
                do {
                    try handler.perform([request])
                } catch {
                    return []
                }
                
                let observations = request.results ?? []
                return observations.compactMap { obs -> RecognizedText? in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    
                    let bb = obs.boundingBox
                    // Vision uses bottom-left origin; flip Y to top-left
                    let normalizedBounds = CGRect(
                        x: bb.minX,
                        y: 1.0 - bb.maxY,
                        width: bb.width,
                        height: bb.height
                    )
                    
                    return RecognizedText(
                        transcript: top.string,
                        normalizedBounds: normalizedBounds
                    )
                }
            }
        }.value
        
        return results
    }
    
    // MARK: - OCR Processing
    
    /// Processes OCR text observations into scan candidates via lexicon resolution.
    /// Bounds are already image-normalized (0…1) from Vision.
    /// Unresolved words (not found in the lexicon) are dropped entirely — they
    /// produce low-value results and clutter the display.
    private func processOCRTexts(
        _ texts: [RecognizedText]
    ) -> (candidates: [ScanCandidate], unresolved: [String]) {
        var candidates: [ScanCandidate] = []
        var unresolved: [String] = []
        var seenLemmas = Set<String>()
        
        for text in texts {
            let tokens = text.transcript
                .components(separatedBy: CharacterSet.whitespaces)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty }
            
            for token in tokens {
                let normalized = normalizer.normalize(token)
                guard !normalized.isEmpty else { continue }
                
                let resolution = lexicon.resolve(
                    observed: token,
                    normalized: normalized,
                    language: language
                )
                
                let lemmaKey = resolution.lemma.lowercased()
                guard !seenLemmas.contains(lemmaKey) else { continue }
                seenLemmas.insert(lemmaKey)
                
                let wasResolved = resolution.translation != nil || language == .english
                if !wasResolved {
                    unresolved.append(token)
                    continue  // Drop unresolved words from candidates
                }

                let candidate = ScanCandidate(
                    language: resolution.language,
                    lemma: resolution.lemma,
                    translation: resolution.translation,
                    source: .ocr,
                    bounds: text.normalizedBounds,
                    confidence: 0.95,
                    originLabel: token
                )
                candidates.append(candidate)
            }
        }
        
        return (candidates, unresolved)
    }
}

// MARK: - CGImagePropertyOrientation

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Language Vision Extensions

extension Language {
    /// BCP-47 language codes for VNRecognizeTextRequest, ordered by priority.
    /// The selected language is listed first, with English as fallback for mixed-language scenes.
    var visionLanguageCodes: [String] {
        switch self {
        case .english: return ["en-US"]
        case .spanish: return ["es-ES", "en-US"]
        case .french:  return ["fr-FR", "en-US"]
        case .german:  return ["de-DE", "en-US"]
        }
    }
}
