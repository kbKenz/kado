import Foundation

/// Parse the entire visible numeric draft; invalid/empty text must never
/// fall back to a previously valid bound value. Grouping is intentionally
/// excluded for these decimal-pad fields.
public enum GoalProgressNumber {
    public static func parse(_ text: String, locale: Locale) -> Double? {
        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        var sign = ""
        if input.first == "-" || input.first == "+" { sign = String(input.removeFirst()) }
        let separator = locale.decimalSeparator ?? "."
        let parts = input.components(separatedBy: separator)
        guard parts.count <= 2, !parts.joined().isEmpty else { return nil }
        var normalized: [String] = []
        for part in parts {
            var digits = ""
            for character in part {
                guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return nil }
                digits += String(digit)
            }
            normalized.append(digits)
        }
        guard let value = Double(sign + normalized.joined(separator: ".")), value.isFinite else { return nil }
        return value
    }
}
