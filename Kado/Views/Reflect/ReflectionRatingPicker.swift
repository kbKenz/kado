import SwiftUI
import KadoCore

/// A 1 to 10 choice that can stay unset. Tapping the chosen value
/// again clears it. One row when it fits, two rows of five when not.
struct ReflectionRatingPicker: View {
    let question: ReflectionQuestion
    @Binding var value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: question.prompt)
                    .font(.headline)
                    .foregroundStyle(Color.kadoForeground)
                Spacer()
                Group {
                    if let value { Text("\(Int(value)) / 10") } else { Text("Not rated") }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.kadoForegroundSecondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { buttons(1...10) }
                VStack(spacing: 6) {
                    HStack(spacing: 6) { buttons(1...5) }
                    HStack(spacing: 6) { buttons(6...10) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func buttons(_ range: ClosedRange<Int>) -> some View {
        ForEach(range, id: \.self) { number in
            let selected = value.map { Int($0) == number } ?? false
            Button {
                value = selected ? nil : Double(number)
            } label: {
                Text(verbatim: "\(number)")
                    .font(.callout.monospacedDigit().weight(selected ? .bold : .regular))
                    .frame(minWidth: 28, minHeight: 36)
                    .frame(maxWidth: .infinity)
                    .background(
                        selected ? Color.kadoAccent : Color.kadoForeground.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .foregroundStyle(selected ? Color.kadoBackground : Color.kadoForeground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(number) of 10"))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(AccessibilityID.Reflect.ratingValue(question.id, number))
        }
    }
}

#Preview("Ratings") {
    @Previewable @State var overall: Double? = 7
    @Previewable @State var energy: Double?
    VStack(spacing: 24) {
        ReflectionRatingPicker(question: ReflectionCatalog.ratings[0], value: $overall)
        ReflectionRatingPicker(question: ReflectionCatalog.ratings[1], value: $energy)
    }
    .padding()
    .background(Color.kadoBackground)
}

#Preview("Ratings, Dark XXXL") {
    @Previewable @State var overall: Double? = 3
    ReflectionRatingPicker(question: ReflectionCatalog.ratings[0], value: $overall)
        .padding()
        .background(Color.kadoBackground)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
