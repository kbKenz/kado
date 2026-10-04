import Foundation
import Testing
@testable import Kado

/// On-device speech models exist per region (en-US, en-GB, …), not for
/// every locale a phone can be set to. A phone set to en-KG should
/// still dictate English rather than lose the mic.
@Suite("SpeechLocaleSelection")
struct SpeechLocaleSelectionTests {

    @Test("The exact locale wins when it has an on-device model")
    func exactLocale() {
        let picked = SpeechLocaleSelection.locale(for: Locale(identifier: "fr-FR")) { _ in true }
        #expect(picked?.identifier == "fr-FR")
    }

    @Test("Falls back to the base language when the region has no model")
    func fallsBackToLanguage() {
        let picked = SpeechLocaleSelection.locale(for: Locale(identifier: "en-KG")) {
            $0.identifier != "en-KG"
        }
        #expect(picked?.identifier == "en")
    }

    @Test("No locale when neither has an on-device model")
    func noModel() {
        #expect(SpeechLocaleSelection.locale(for: Locale(identifier: "ky-KG")) { _ in false } == nil)
    }
}
