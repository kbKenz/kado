import Foundation
import Observation
import SwiftData
import KadoCore

/// Draft state for the New Habit sheet. Holds one stored property
/// per kind's associated value so toggling between `frequencyKind`
/// or `typeKind` options doesn't wipe partially-entered data.
/// Reused for edit mode via `init(editing:)`.
///
/// The goal, category, colour and icon live in `suggestions`, which
/// knows who set each one: setting them here is the person's choice,
/// and title suggestions never change them again.
@MainActor
@Observable
final class NewHabitFormModel {
    var name: String = ""

    /// The goal, category, colour and icon, with who set each.
    let suggestions: SuggestionDraft

    var selectedGoalID: UUID? {
        get { suggestions.goalID }
        set { suggestions.userSetGoal(newValue) }
    }

    /// `nil` means not set.
    var category: ItemCategory? {
        get { suggestions.category }
        set { suggestions.userSetCategory(newValue) }
    }

    var frequencyKind: FrequencyKind = .daily
    var daysPerWeek: Int = 3
    var specificDays: Set<Weekday> = [.monday, .wednesday, .friday]
    var everyNDays: Int = 2

    var typeKind: HabitTypeKind = .binary
    var counterTarget: Double = 1
    var timerTargetMinutes: Int = 10

    var color: HabitColor {
        get { suggestions.color }
        set { suggestions.userSetColor(newValue) }
    }

    var icon: String {
        get { suggestions.icon }
        set { suggestions.userSetIcon(newValue) }
    }

    /// Per-habit reminder toggle. When true, `save(in:)` writes the
    /// time components onto the `HabitRecord`; the scheduler derives
    /// the actual days-due from `frequency`.
    var remindersEnabled: Bool = false

    /// DatePicker-bound value. Only the hour + minute components are
    /// persisted — the day portion is cosmetic and discarded on save.
    /// Survives `remindersEnabled` toggles so the user's chosen time
    /// isn't wiped when they explore the toggle.
    var reminderTime: Date = NewHabitFormModel.defaultReminderTime()

    /// Resolve this identity from the current store at save time.
    /// Draft state must not retain an object from a swapped store.
    private(set) var editingHabitID: UUID?

    enum FrequencyKind: Hashable, CaseIterable {
        case daily, daysPerWeek, specificDays, everyNDays
    }

    enum HabitTypeKind: Hashable, CaseIterable {
        case binary, counter, timer, negative
    }

    /// A new habit. `goalID` starts it on a goal as the person's choice
    /// (from Goal detail), so suggestions never change it.
    init(goalID: UUID? = nil) {
        suggestions = SuggestionDraft(kind: .habit)
        if let goalID { suggestions.presetGoal(goalID) }
    }

    /// Default is 9:00 today in the current calendar. Stored on the
    /// type so both fresh and edit inits converge on the same seed
    /// when the record doesn't yet carry a configured time.
    static func defaultReminderTime(calendar: Calendar = .current, now: Date = .now) -> Date {
        calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
    }

    static func time(fromHour hour: Int, minute: Int, calendar: Calendar = .current, now: Date = .now) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }

    /// Pre-fill with values and retain only the current habit identity.
    init(editing record: HabitRecord) {
        suggestions = SuggestionDraft(kind: .habit, isEditing: true)
        self.editingHabitID = record.id
        self.name = record.name
        switch record.frequency {
        case .daily:
            self.frequencyKind = .daily
        case .daysPerWeek(let n):
            self.frequencyKind = .daysPerWeek
            self.daysPerWeek = n
        case .specificDays(let days):
            self.frequencyKind = .specificDays
            self.specificDays = days
        case .everyNDays(let n):
            self.frequencyKind = .everyNDays
            self.everyNDays = n
        }
        switch record.type {
        case .binary:
            self.typeKind = .binary
        case .counter(let target):
            self.typeKind = .counter
            self.counterTarget = target
        case .timer(let seconds):
            self.typeKind = .timer
            // Round so sub-minute targets surface at least 1 minute on edit
            // rather than silently truncating to 0. Users editing a
            // 90-second habit see "2 min" rather than "1 min."
            self.timerTargetMinutes = max(1, Int((seconds / 60).rounded()))
        case .negative:
            self.typeKind = .negative
        }
        // Saved values are the person's; an empty category or the
        // circle icon can still get a suggestion chip.
        suggestions.load(category: record.category, goalID: record.goal?.id, icon: record.icon, color: record.color)
        self.remindersEnabled = record.remindersEnabled
        self.reminderTime = Self.time(
            fromHour: record.reminderHour,
            minute: record.reminderMinute
        )
    }

    var isEditing: Bool { editingHabitID != nil }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var frequency: Frequency {
        switch frequencyKind {
        case .daily: .daily
        case .daysPerWeek: .daysPerWeek(daysPerWeek)
        case .specificDays: .specificDays(specificDays)
        case .everyNDays: .everyNDays(everyNDays)
        }
    }

    var type: HabitType {
        switch typeKind {
        case .binary: .binary
        case .counter: .counter(target: counterTarget)
        case .timer: .timer(targetSeconds: TimeInterval(timerTargetMinutes) * 60)
        case .negative: .negative
        }
    }

    var isValid: Bool {
        guard !trimmedName.isEmpty else { return false }
        switch frequencyKind {
        case .daily: break
        case .daysPerWeek: guard (1...7).contains(daysPerWeek) else { return false }
        case .specificDays: guard !specificDays.isEmpty else { return false }
        case .everyNDays: guard everyNDays >= 1 else { return false }
        }
        switch typeKind {
        case .binary, .negative: break
        case .counter: guard counterTarget > 0 else { return false }
        case .timer: guard timerTargetMinutes > 0 else { return false }
        }
        // .negative + .daysPerWeek has ambiguous semantics (streak counts
        // completions that represent failures) — reject the combination
        // until there's a clear product call.
        if typeKind == .negative && frequencyKind == .daysPerWeek {
            return false
        }
        return true
    }

    /// `createdAt` defaults to the caller's clock, but callers that
    /// know the user's day boundary should pass the logical instant —
    /// it anchors the `everyNDays` cycle and bounds the score, so a
    /// habit created at 2am under a 4 AM rollover belongs to the day
    /// the user still thinks they're in.
    func build(createdAt: Date = .now) -> HabitRecord {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        return HabitRecord(
            name: trimmedName,
            frequency: frequency,
            type: type,
            createdAt: createdAt,
            color: color,
            icon: icon,
            remindersEnabled: remindersEnabled,
            reminderHour: components.hour ?? 9,
            reminderMinute: components.minute ?? 0
        )
    }

    /// Inserts a new record or mutates the existing one in place,
    /// then saves. Returns the final record (new or edited).
    @discardableResult
    func save(in context: ModelContext, createdAt: Date = .now) throws -> HabitRecord {
        let goal: GoalRecord?
        if let selectedGoalID {
            let goals = try context.fetch(FetchDescriptor<GoalRecord>())
            guard let selected = goals.first(where: { $0.id == selectedGoalID }) else {
                throw SaveError.goalUnavailable
            }
            goal = selected
        } else {
            goal = nil
        }
        let record: HabitRecord
        if let editingHabitID {
            let habits = try context.fetch(FetchDescriptor<HabitRecord>())
            guard let existing = habits.first(where: { $0.id == editingHabitID }) else {
                throw SaveError.habitUnavailable
            }
            record = existing
        } else {
            record = build(createdAt: createdAt)
            record.sortOrder = HabitSortOrder.nextSortOrder(in: context)
            context.insert(record)
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        do {
            record.name = trimmedName
            record.frequency = frequency
            record.type = type
            record.color = color
            record.icon = icon
            record.category = category
            record.remindersEnabled = remindersEnabled
            record.reminderHour = components.hour ?? 9
            record.reminderMinute = components.minute ?? 0
            record.goal = goal
            try context.save()
            WidgetReloader.reloadAll(using: context)
            return record
        } catch {
            context.rollback()
            throw error
        }
    }

    private enum SaveError: LocalizedError {
        case habitUnavailable, goalUnavailable

        var errorDescription: String? {
            switch self {
            case .habitUnavailable:
                return String(localized: "This habit is no longer in the current store.")
            case .goalUnavailable:
                return String(localized: "This goal is no longer available. Choose another goal or remove the assignment.")
            }
        }
    }
}
