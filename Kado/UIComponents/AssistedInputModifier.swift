import SwiftUI

extension View {
    /// Adds on-device dictation (mic) and text cleanup (✨, with Undo)
    /// to a text field. Each control hides itself where its engine is
    /// unavailable, and both hide when the field is disabled.
    ///
    /// Apply it last, after the field's own `.accessibilityIdentifier`:
    /// an identifier applied outside it would stamp the buttons too.
    /// `identifier` is the field's identifier; the buttons derive theirs
    /// from it (`AccessibilityID.AssistedInput`).
    func assistedInput(
        _ text: Binding<String>,
        characterLimit: Int? = nil,
        identifier: String
    ) -> some View {
        modifier(AssistedInputModifier(text: text, characterLimit: characterLimit, identifier: identifier))
    }
}

struct AssistedInputModifier: ViewModifier {
    @Binding var text: String
    let characterLimit: Int?
    let identifier: String

    @Environment(\.speechTranscriber) private var transcriber
    @Environment(\.textCleaner) private var cleaner
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    /// Built in `.onAppear`: the environment's services are not
    /// readable yet when `@State` is seeded.
    @State private var model: AssistedInputModel?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                content
                if let model, isEnabled {
                    controls(model)
                }
            }
            if let model, isEnabled {
                feedback(model)
            }
        }
        .onAppear {
            if model == nil {
                model = AssistedInputModel(transcriber: transcriber, cleaner: cleaner, characterLimit: characterLimit)
            }
        }
        .onChange(of: text) { _, newValue in model?.textDidChange(to: newValue) }
        .onDisappear { model?.stopIfRecording() }
    }

    // MARK: - Buttons

    @ViewBuilder
    private func controls(_ model: AssistedInputModel) -> some View {
        if model.canRecord {
            Button {
                model.toggleRecording(text: $text)
            } label: {
                Image(systemName: model.isRecording ? "stop.circle.fill" : "mic")
                    .symbolEffect(.pulse, isActive: model.isRecording && !reduceMotion)
                    .foregroundStyle(model.isRecording ? Color.red : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(model.isRecording ? Text("Stop dictation") : Text("Dictate"))
            .accessibilityIdentifier(AccessibilityID.AssistedInput.mic(identifier))
        }
        if model.state == .cleaning {
            ProgressView()
                .controlSize(.small)
                .tint(.secondary)
                .accessibilityLabel(Text("Cleaning up text"))
        } else if model.canClean(text) {
            Button {
                model.clean(text: $text)
            } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Clean up text"))
            .accessibilityIdentifier(AccessibilityID.AssistedInput.clean(identifier))
        }
    }

    // MARK: - Undo and failures

    @ViewBuilder
    private func feedback(_ model: AssistedInputModel) -> some View {
        if model.undoSnapshot != nil {
            Button {
                model.undo(text: $text)
            } label: {
                Label("Undo cleanup", systemImage: "arrow.uturn.backward")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .accessibilityIdentifier(AccessibilityID.AssistedInput.undo(identifier))
        } else if case .failed(let error) = model.state {
            failureMessage(error, model: model)
        }
    }

    private func failureMessage(_ error: AssistedInputError, model: AssistedInputModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(message(for: error))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if error == .permissionDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.footnote)
                .buttonStyle(.borderless)
            }
            Spacer(minLength: 0)
            Button {
                model.dismissFailure()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Dismiss"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.AssistedInput.failure(identifier))
    }

    private func message(for error: AssistedInputError) -> LocalizedStringKey {
        switch error {
        case .permissionDenied:
            return "Allow microphone and speech recognition for Kadō in Settings to dictate."
        case .unavailable:
            return "Not available on this device right now. Your text is unchanged."
        case .failed:
            return "That didn't work. Your text is unchanged; try again."
        }
    }
}

#Preview("Available") {
    @Previewable @State var title = "um so read read more books"
    @Previewable @State var notes = ""
    Form {
        TextField("Task title", text: $title)
            .assistedInput($title, identifier: "preview.title")
        TextField("Notes (optional)", text: $notes, axis: .vertical)
            .lineLimit(3...6)
            .assistedInput($notes, characterLimit: 500, identifier: "preview.notes")
    }
    .environment(\.speechTranscriber, MockSpeechTranscriber())
    .environment(\.textCleaner, MockTextCleaner(result: .success("Read more books.")))
}

#Preview("Unavailable and disabled") {
    @Previewable @State var title = "Read more books"
    Form {
        Section("No engines (iOS 18, Apple Intelligence off)") {
            TextField("Task title", text: $title)
                .assistedInput($title, identifier: "preview.none")
        }
        .environment(\.speechTranscriber, MockSpeechTranscriber(isAvailable: false))
        .environment(\.textCleaner, MockTextCleaner(isAvailable: false))
        Section("Disabled (imported task)") {
            TextField("Task title", text: $title)
                .assistedInput($title, identifier: "preview.disabled")
                .disabled(true)
        }
        .environment(\.speechTranscriber, MockSpeechTranscriber())
        .environment(\.textCleaner, MockTextCleaner())
    }
}

#Preview("Dark") {
    @Previewable @State var title = "walked 5km felt felt great"
    Form {
        TextField("Task title", text: $title)
            .assistedInput($title, identifier: "preview.dark")
    }
    .environment(\.speechTranscriber, MockSpeechTranscriber())
    .environment(\.textCleaner, MockTextCleaner(result: .success("Walked 5 km. Felt great.")))
    .preferredColorScheme(.dark)
}
