import Combine
import Foundation

final class L10n: ObservableObject {
    enum Choice: String, CaseIterable {
        case system, en, simplifiedChinese = "zh-Hans"

        var title: String {
            switch self {
            case .system: return L10n.text("跟随系统")
            case .en: return "English"
            case .simplifiedChinese: return "简体中文"
            }
        }
    }

    static let shared = L10n()
    @Published private(set) var choice: Choice

    private static let storageKey = "StickerLanguage"
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues:
        ["en", "zh-Hans"].compactMap { language in
            guard let url = Bundle.main.url(forResource: language, withExtension: "lproj"),
                  let bundle = Bundle(url: url) else { return nil }
            return (language, bundle)
        }
    )

    private init() {
        choice = UserDefaults.standard.string(forKey: Self.storageKey)
            .flatMap(Choice.init(rawValue:)) ?? .system
    }

    func select(_ choice: Choice) {
        guard self.choice != choice else { return }
        self.choice = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.storageKey)
    }

    var locale: Locale {
        choice == .system ? .current : Locale(identifier: choice.rawValue)
    }

    static var language: String {
        if shared.choice != .system { return shared.choice.rawValue }
        return Bundle.main.preferredLocalizations.first ?? "en"
    }

    static func text(_ key: String) -> String {
        let bundle = bundles[language] ?? Bundle.main
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: shared.locale, arguments: arguments)
    }
}
