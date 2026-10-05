import Testing
import SwiftUI
@testable import Kado
import KadoCore

@Suite("EnvironmentValues service registration")
struct EnvironmentValuesServicesTests {
    @Test("Default habitScoreCalculator is a DefaultHabitScoreCalculator")
    func defaultCalculatorRegistered() {
        let env = EnvironmentValues()
        #expect(env.habitScoreCalculator is DefaultHabitScoreCalculator)
    }
}

/// Assisted input must never reach the microphone or the language model
/// unless `KadoApp` injects the real services, so previews and tests
/// default to stand-ins that report themselves unavailable.
@MainActor
@Suite("EnvironmentValues assisted input defaults")
struct AssistedInputEnvironmentTests {
    @Test("Default speechTranscriber is unavailable")
    func defaultSpeechTranscriberUnavailable() {
        let env = EnvironmentValues()
        #expect(env.speechTranscriber is UnavailableSpeechTranscriber)
        #expect(!env.speechTranscriber.isAvailable)
    }

    @Test("Default textCleaner is unavailable")
    func defaultTextCleanerUnavailable() {
        let env = EnvironmentValues()
        #expect(env.textCleaner is UnavailableTextCleaner)
        #expect(!env.textCleaner.isAvailable)
    }

    @Test("Unavailable cleaner throws .unavailable and never returns text")
    func unavailableCleanerThrows() async {
        await #expect(throws: AssistedInputError.unavailable) {
            _ = try await UnavailableTextCleaner().clean("hello")
        }
    }

    @Test("Unavailable transcriber's stream fails with .unavailable")
    func unavailableTranscriberFails() async {
        await #expect(throws: AssistedInputError.unavailable) {
            for try await _ in UnavailableSpeechTranscriber().transcribe() {}
        }
    }

    @Test("Default itemSuggester is unavailable")
    func defaultItemSuggesterUnavailable() {
        let env = EnvironmentValues()
        #expect(env.itemSuggester is UnavailableItemSuggester)
        #expect(!env.itemSuggester.isAvailable)
    }

    @Test("Unavailable suggester throws .unavailable and never answers")
    func unavailableSuggesterThrows() async {
        let request = ItemSuggestionRequest(title: "Read 20 pages", kind: .habit, goals: [])
        await #expect(throws: ItemSuggestionError.unavailable) {
            _ = try await UnavailableItemSuggester().suggest(request)
        }
    }
}
