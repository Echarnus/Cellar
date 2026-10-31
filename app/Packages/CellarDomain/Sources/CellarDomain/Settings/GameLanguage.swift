import Foundation

/// The language a game — and the store client that starts it — runs in.
///
/// Left alone, Wine takes its locale from whatever `LANG`/`LC_*` the launching process happened to
/// have: a Terminal on a Belgian Mac exports `nl_BE.UTF-8`, the app exports nothing. Steam takes its
/// interface language from Wine, and a game Cellar downloaded itself (no appmanifest) takes Steam's.
/// That is how a Mac set to English got Steam and Planet Coaster in Dutch. So Cellar always says
/// which language it wants: by default the Mac's own, and the player can pick another for every
/// game (Settings, `cellar language set`) or for one (`cellar language set <game>`).
///
/// Only languages Steam ships *and* macOS has a locale for are listed — Wine needs a real locale
/// to switch to, and a language it cannot get falls back to English, which is what happens to any
/// language not in this table.
public enum GameLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case german = "de"
    case french = "fr"
    case italian = "it"
    case spanish = "es"
    case latinAmericanSpanish = "es-419"
    case portuguese = "pt"
    case brazilianPortuguese = "pt-BR"
    case dutch = "nl"
    case polish = "pl"
    case russian = "ru"
    case ukrainian = "uk"
    case czech = "cs"
    case hungarian = "hu"
    case romanian = "ro"
    case bulgarian = "bg"
    case greek = "el"
    case turkish = "tr"
    case swedish = "sv"
    case danish = "da"
    case norwegian = "nb"
    case finnish = "fi"
    case japanese = "ja"
    case korean = "ko"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    /// The short code a player types and a settings file stores: `en`, `pt-BR`, `zh-Hans`.
    public var code: String { rawValue }

    /// The language's name in that language, as every OS's language list shows it — a player who
    /// can't read the current one can still find their own.
    public var nativeName: String {
        switch self {
        case .english:              return "English"
        case .german:               return "Deutsch"
        case .french:               return "Français"
        case .italian:              return "Italiano"
        case .spanish:              return "Español (España)"
        case .latinAmericanSpanish: return "Español (Latinoamérica)"
        case .portuguese:           return "Português (Portugal)"
        case .brazilianPortuguese:  return "Português (Brasil)"
        case .dutch:                return "Nederlands"
        case .polish:               return "Polski"
        case .russian:              return "Русский"
        case .ukrainian:            return "Українська"
        case .czech:                return "Čeština"
        case .hungarian:            return "Magyar"
        case .romanian:             return "Română"
        case .bulgarian:            return "Български"
        case .greek:                return "Ελληνικά"
        case .turkish:              return "Türkçe"
        case .swedish:              return "Svenska"
        case .danish:               return "Dansk"
        case .norwegian:            return "Norsk"
        case .finnish:              return "Suomi"
        case .japanese:             return "日本語"
        case .korean:               return "한국어"
        case .simplifiedChinese:    return "简体中文"
        case .traditionalChinese:   return "繁體中文"
        }
    }

    /// Steam's API language name — the value of `HKCU\Software\Valve\Steam\Language`, `-language`,
    /// and an appmanifest's `UserConfig` `language`. Steam's own spellings, `koreana` included.
    public var steamName: String {
        switch self {
        case .english:              return "english"
        case .german:               return "german"
        case .french:               return "french"
        case .italian:              return "italian"
        case .spanish:              return "spanish"
        case .latinAmericanSpanish: return "latam"
        case .portuguese:           return "portuguese"
        case .brazilianPortuguese:  return "brazilian"
        case .dutch:                return "dutch"
        case .polish:               return "polish"
        case .russian:              return "russian"
        case .ukrainian:            return "ukrainian"
        case .czech:                return "czech"
        case .hungarian:            return "hungarian"
        case .romanian:             return "romanian"
        case .bulgarian:            return "bulgarian"
        case .greek:                return "greek"
        case .turkish:              return "turkish"
        case .swedish:              return "swedish"
        case .danish:               return "danish"
        case .norwegian:            return "norwegian"
        case .finnish:              return "finnish"
        case .japanese:             return "japanese"
        case .korean:               return "koreana"
        case .simplifiedChinese:    return "schinese"
        case .traditionalChinese:   return "tchinese"
        }
    }

    /// The POSIX locale Wine is started with. Each is one macOS ships in `/usr/share/locale` — a
    /// name `setlocale` rejects leaves Wine in English. Latin-American Spanish has no macOS locale
    /// of its own, so Wine gets Spain's; Steam is still told `latam`.
    public var posixLocale: String {
        switch self {
        case .english:              return "en_US.UTF-8"
        case .german:               return "de_DE.UTF-8"
        case .french:               return "fr_FR.UTF-8"
        case .italian:              return "it_IT.UTF-8"
        case .spanish, .latinAmericanSpanish: return "es_ES.UTF-8"
        case .portuguese:           return "pt_PT.UTF-8"
        case .brazilianPortuguese:  return "pt_BR.UTF-8"
        case .dutch:                return "nl_NL.UTF-8"
        case .polish:               return "pl_PL.UTF-8"
        case .russian:              return "ru_RU.UTF-8"
        case .ukrainian:            return "uk_UA.UTF-8"
        case .czech:                return "cs_CZ.UTF-8"
        case .hungarian:            return "hu_HU.UTF-8"
        case .romanian:             return "ro_RO.UTF-8"
        case .bulgarian:            return "bg_BG.UTF-8"
        case .greek:                return "el_GR.UTF-8"
        case .turkish:              return "tr_TR.UTF-8"
        case .swedish:              return "sv_SE.UTF-8"
        case .danish:               return "da_DK.UTF-8"
        case .norwegian:            return "no_NO.UTF-8"
        case .finnish:              return "fi_FI.UTF-8"
        case .japanese:             return "ja_JP.UTF-8"
        case .korean:               return "ko_KR.UTF-8"
        case .simplifiedChinese:    return "zh_CN.UTF-8"
        case .traditionalChinese:   return "zh_TW.UTF-8"
        }
    }

    /// Blizzard's locale for the Battle.net installer's `--lang`, where Blizzard has one. Anything
    /// else installs in English, which is what it always did.
    public var blizzardLocale: String? {
        switch self {
        case .english:              return "enUS"
        case .german:               return "deDE"
        case .french:               return "frFR"
        case .italian:              return "itIT"
        case .spanish:              return "esES"
        case .latinAmericanSpanish: return "esMX"
        case .brazilianPortuguese:  return "ptBR"
        case .polish:               return "plPL"
        case .russian:              return "ruRU"
        case .turkish:              return "trTR"
        case .japanese:             return "jaJP"
        case .korean:               return "koKR"
        case .simplifiedChinese:    return "zhCN"
        case .traditionalChinese:   return "zhTW"
        default:                    return nil
        }
    }

    /// The variables that pin Wine to this language. `LC_ALL` rather than `LC_MESSAGES` alone: an
    /// inherited `LC_ALL` would otherwise win over anything set here, and a launch should not
    /// depend on which shell it came from.
    public var environment: [String: String] {
        ["LANG": posixLocale, "LC_ALL": posixLocale]
    }

    /// A code, a Steam name or an English name, as a player might type any of them. Case and
    /// `_`/`-` don't matter: `pt_BR`, `pt-br` and `brazilian` are all Brazilian Portuguese.
    public static func named(_ text: String) -> GameLanguage? {
        let wanted = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "_", with: "-")
        guard !wanted.isEmpty else { return nil }
        return allCases.first { $0.code.lowercased() == wanted }
            ?? allCases.first { $0.steamName == wanted }
            ?? allCases.first { $0.nativeName.lowercased() == wanted }
            ?? allCases.first { String(describing: $0).lowercased() == wanted.replacingOccurrences(of: " ", with: "") }
    }

    /// The best match for one BCP-47 language tag as macOS reports it (`en-BE`, `pt-BR`,
    /// `zh-Hant-TW`, `es-419`), or nil if Cellar has nothing close.
    public static func matching(languageTag tag: String) -> GameLanguage? {
        let parts = tag.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let language = parts.first?.lowercased() else { return nil }
        let rest = parts.dropFirst().map { $0.lowercased() }
        switch language {
        case "pt":
            return rest.contains("br") ? .brazilianPortuguese : .portuguese
        case "es":
            // Spain, or nothing more specific, is Spain's Spanish; any other region is Latin America's.
            return rest.isEmpty || rest.contains("es") ? .spanish : .latinAmericanSpanish
        case "zh":
            if rest.contains("hant") || rest.contains("tw") || rest.contains("hk") || rest.contains("mo") {
                return .traditionalChinese
            }
            return .simplifiedChinese
        case "no", "nb", "nn":
            return .norwegian
        default:
            return allCases.first { $0.code == language }
        }
    }

    /// The Mac's language: the first of the player's preferred languages (System Settings →
    /// General → Language & Region) that Cellar can run a game in, else English. Not
    /// `Locale.current`, which mixes in the *region* — an English Mac in Belgium is `en_BE`, and
    /// its formats say nothing about which language the player reads.
    public static func system(preferredLanguages: [String] = Locale.preferredLanguages) -> GameLanguage {
        preferredLanguages.lazy.compactMap(matching(languageTag:)).first ?? .english
    }
}
