import Foundation

@available(iOS 17.0, *)
@MainActor
@Observable
final class AppSettings {
    private static let languageKey = "settings.sourceLanguage"
    private static let translationKey = "settings.showTranslation"
    private static let categoriesKey = "settings.showCategories"
    private static let contextualKey = "settings.contextualSuggestions"
    private static let highContrastSelectionKey = "settings.highContrastSelection"

    var sourceLanguage: Language {
        didSet { UserDefaults.standard.set(sourceLanguage.rawValue, forKey: Self.languageKey) }
    }

    var showTranslation: Bool {
        didSet { UserDefaults.standard.set(showTranslation, forKey: Self.translationKey) }
    }

    var showCategories: Bool {
        didSet { UserDefaults.standard.set(showCategories, forKey: Self.categoriesKey) }
    }

    var contextualSuggestionsEnabled: Bool {
        didSet { UserDefaults.standard.set(contextualSuggestionsEnabled, forKey: Self.contextualKey) }
    }

    /// When enabled, selected rows show a checkmark icon alongside the green background,
    /// providing a non-color-only signal for selection state.
    var highContrastSelection: Bool {
        didSet { UserDefaults.standard.set(highContrastSelection, forKey: Self.highContrastSelectionKey) }
    }

    /// Whether the device supports Apple Intelligence (iOS 26+).
    static var deviceSupportsAppleIntelligence: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// Combined check: device supports it AND user hasn't turned it off.
    var shouldShowContextualSuggestions: Bool {
        Self.deviceSupportsAppleIntelligence && contextualSuggestionsEnabled
    }

    init() {
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: Self.languageKey),
           let lang = Language(rawValue: raw) {
            self.sourceLanguage = lang
        } else {
            self.sourceLanguage = .spanish
        }

        if defaults.object(forKey: Self.translationKey) != nil {
            self.showTranslation = defaults.bool(forKey: Self.translationKey)
        } else {
            self.showTranslation = true
        }

        if defaults.object(forKey: Self.categoriesKey) != nil {
            self.showCategories = defaults.bool(forKey: Self.categoriesKey)
        } else {
            self.showCategories = true
        }

        if defaults.object(forKey: Self.contextualKey) != nil {
            self.contextualSuggestionsEnabled = defaults.bool(forKey: Self.contextualKey)
        } else {
            self.contextualSuggestionsEnabled = true  // Default ON
        }

        if defaults.object(forKey: Self.highContrastSelectionKey) != nil {
            self.highContrastSelection = defaults.bool(forKey: Self.highContrastSelectionKey)
        } else {
            self.highContrastSelection = false  // Default OFF, opt-in
        }
    }
}
