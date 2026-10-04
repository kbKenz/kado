import Foundation

/// Picks the locale to dictate in. On-device speech models exist per
/// region (en-US, en-GB, …), not for every locale a phone can be set
/// to, so a phone set to en-KG falls back to plain "en" instead of
/// losing the mic.
nonisolated enum SpeechLocaleSelection {
    /// The first of `locale` and its base language that
    /// `hasOnDeviceModel` accepts, or `nil` if neither does.
    static func locale(for locale: Locale, hasOnDeviceModel: (Locale) -> Bool) -> Locale? {
        var candidates = [locale]
        if let language = locale.language.languageCode?.identifier, language != locale.identifier {
            candidates.append(Locale(identifier: language))
        }
        return candidates.first(where: hasOnDeviceModel)
    }
}
