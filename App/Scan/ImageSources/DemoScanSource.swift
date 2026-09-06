import UIKit
import os

/// Demo mode scene config: pairs an image asset with a classification JSON data asset.
@available(iOS 18.0, *)
struct DemoScene: Identifiable, Hashable {
    let id: String
    let imageAssetName: String
    let classificationDataAssetName: String?

    static let apple = DemoScene(
        id: "apple",
        imageAssetName: "vertical demo",
        classificationDataAssetName: "apple_classification_mock"
    )
    
    static let barca = DemoScene(
        id: "barca",
        imageAssetName: "PreloadCapture_A8A492FE-164B-4AD7-ABBB-14776F8C5FB5",
        classificationDataAssetName: "barca_classification_mock")
    
    static let atm = DemoScene(
        id: "atm",
        imageAssetName: "atm",
        classificationDataAssetName: "atm_classification_mock")

    static let florero = DemoScene(
        id: "florero",
        imageAssetName: "PreloadCapture_C77C53E7-36B6-46EE-A4A5-65691FE9A7A8",
        classificationDataAssetName: "florero_classification_mock")
    
    /// All scenes available in the demo picker.
    static let all: [DemoScene] = [.apple, .barca, .atm, .florero]
}

/// A `ScanSource` that serves a static image from the asset catalog and replays
/// saved Apple classification results from a Data asset (Media.xcassets).
///
/// Supports switching scenes at runtime via `loadScene(_:)`.
@MainActor
@available(iOS 18.0, *)
final class DemoScanSource: ScanSource {

    // MARK: - State

    private(set) var scene: DemoScene

    // MARK: - Classification Mock

    /// In demo mode, use these hits instead of VNClassifyImageRequest output.
    /// Sorted by confidence descending. Accessed by ScanController directly.
    private(set) var mockClassificationHits: [(label: String, confidence: Float)]

    // MARK: - Init

    init(scene: DemoScene = .apple) {
        self.scene = scene
        self.mockClassificationHits = Self.loadClassificationHits(for: scene)

        #if DEBUG
        Self.logLoadStatus(scene: scene, hits: mockClassificationHits)
        #endif
    }

    // MARK: - Scene Switching

    /// Switch to a new demo scene. Reloads classification data.
    func loadScene(_ newScene: DemoScene) {
        guard newScene.id != scene.id else { return }
        scene = newScene
        mockClassificationHits = Self.loadClassificationHits(for: newScene)

        #if DEBUG
        Self.logLoadStatus(scene: newScene, hits: mockClassificationHits)
        #endif
    }

    // MARK: - Capture

    func capturePhoto() async throws -> UIImage {
        guard let image = UIImage(named: scene.imageAssetName) else {
            throw DemoSourceError.imageNotFound
        }
        return image
    }

    // MARK: - Private: Classification Mock Data Decoding

    private struct MockLogEntry: Codable {
        struct Item: Codable {
            let label: String
            let confidence: Float
        }
        let allClassifications: [Item]
    }

    private static func loadClassificationHits(for scene: DemoScene) -> [(label: String, confidence: Float)] {
        guard let assetName = scene.classificationDataAssetName else { return [] }
        return loadClassificationHitsFromDataAsset(named: assetName)
    }

    private static func loadClassificationHitsFromDataAsset(named name: String) -> [(label: String, confidence: Float)] {
        guard let asset = NSDataAsset(name: name) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let entries = try decoder.decode([MockLogEntry].self, from: asset.data)
            let items = entries.first?.allClassifications ?? []
            return items
                .map { (label: $0.label, confidence: $0.confidence) }
                .sorted { $0.confidence > $1.confidence }
        } catch {
            #if DEBUG
            Log.scan.error("Failed to decode \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
            return []
        }
    }

    #if DEBUG
    private static func logLoadStatus(
        scene: DemoScene,
        hits: [(label: String, confidence: Float)]
    ) {
        if UIImage(named: scene.imageAssetName) == nil {
            Log.scan.error("Image \"\(scene.imageAssetName, privacy: .public)\" not found in asset catalog")
        }
        if scene.classificationDataAssetName != nil, hits.isEmpty {
            let assetName = scene.classificationDataAssetName ?? "unknown"
            Log.scan.error("Classification asset \"\(assetName, privacy: .public)\" missing or failed to decode")
        }
    }
    #endif
}

enum DemoSourceError: LocalizedError {
    case imageNotFound

    var errorDescription: String? {
        "Demo image not found in asset catalog."
    }
}
