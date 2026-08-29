import Combine
import Foundation
import SwiftUI

nonisolated enum AppLanguageMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "System Default"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}

@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var mode: AppLanguageMode {
        didSet {
            defaults.set(mode.rawValue, forKey: preferenceKey)
            refreshEffectiveLanguage()
        }
    }

    @Published private(set) var effectiveLanguageIdentifier: String

    var locale: Locale {
        Locale(identifier: effectiveLanguageIdentifier == "zh-Hans" ? "zh-Hans" : "en-US")
    }

    private let defaults: UserDefaults
    private let preferenceKey = "settings.general.language"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = AppLanguageMode(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .system
        effectiveLanguageIdentifier = "en"
        effectiveLanguageIdentifier = Self.resolveLanguage(for: mode)
    }

    func refreshSystemLanguage() {
        guard mode == .system else { return }
        refreshEffectiveLanguage()
    }

    func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: localizationBundle, locale: locale)
    }

    func format(_ key: String.LocalizationValue, arguments: [CVarArg]) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    private func refreshEffectiveLanguage() {
        effectiveLanguageIdentifier = Self.resolveLanguage(for: mode)
    }

    private var localizationBundle: Bundle {
        guard let path = Bundle.main.path(
            forResource: effectiveLanguageIdentifier,
            ofType: "lproj"
        ), let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    private static func resolveLanguage(for mode: AppLanguageMode) -> String {
        switch mode {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .system:
            return resolvePreferredSystemLanguage()
        }
    }

    private static func resolvePreferredSystemLanguage() -> String {
        for identifier in Locale.preferredLanguages {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()

            if normalized == "zh" || normalized.hasPrefix("zh-hans") || normalized.hasPrefix("zh-cn") || normalized.hasPrefix("zh-sg") {
                return "zh-Hans"
            }

            if normalized == "en" || normalized.hasPrefix("en-") {
                return "en"
            }
        }

        return "en"
    }
}

@MainActor
enum L10n {
    static func string(_ key: String.LocalizationValue) -> String {
        LanguageManager.shared.string(key)
    }

    static func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        LanguageManager.shared.format(key, arguments: arguments)
    }
}
