import SwiftUI
import KadoCore

/// What the Sleep and Movement cards show in place of numbers they do
/// not have: a short how-to, "Connect Apple Health" while Health is
/// off, and a one-tap habit template while the category has no habit.
struct InsightsHealthPrompt: View {
    let message: LocalizedStringKey?
    let showsConnect: Bool
    let template: InsightsHabitTemplate?
    let actions: InsightsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.kadoForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsConnect || template != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons }
                    VStack(alignment: .leading, spacing: 8) { buttons }
                }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if showsConnect {
            Button(action: actions.connectHealth) {
                Label("Connect Apple Health", systemImage: "heart.text.square")
            }
            .buttonStyle(.bordered)
            .tint(Color.kadoAccent)
            .accessibilityIdentifier(AccessibilityID.Insights.connectHealth)
        }
        if let template {
            Button {
                actions.addHabitTemplate(template)
            } label: {
                Label(template.buttonTitle, systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .tint(Color.kadoAccent)
            .accessibilityIdentifier(AccessibilityID.Insights.template(template.rawValue))
        }
    }
}

private extension InsightsHabitTemplate {
    var buttonTitle: LocalizedStringKey {
        switch self {
        case .sleep: "Add a sleep habit"
        case .workout: "Add a workout habit"
        }
    }
}

#Preview("Prompt") {
    InsightsHealthPrompt(
        message: "Connect Apple Health to see your nights.",
        showsConnect: true,
        template: .sleep,
        actions: .none
    )
    .padding()
    .background(Color.kadoBackgroundSecondary)
}

#Preview("Dark") {
    InsightsHealthPrompt(
        message: nil,
        showsConnect: false,
        template: .workout,
        actions: .none
    )
    .padding()
    .background(Color.kadoBackgroundSecondary)
    .preferredColorScheme(.dark)
}
