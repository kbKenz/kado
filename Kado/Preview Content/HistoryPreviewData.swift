import Foundation
import KadoCore

/// A few weeks of made-up history, for previews and for the UI suite's
/// `-uiTestInsightsFixture` launch: tasks across categories, binary,
/// counter, timer and negative habits, sessions on a task left open,
/// and gaps of quiet days. Stored, not computed, so every caller sees
/// the same ids (CLAUDE.md, preview fixtures).
enum HistoryPreviewData {
    static let input: InsightsInput = make()

    static let days: [HistoryDay] = HistoryBuilder.days(
        input: input,
        query: HistoryQuery(),
        calendar: .current,
        dayBoundary: DayBoundary()
    )

    private static func make() -> InsightsInput {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let cambridge = UUID()
        let goals = [InsightsGoal(id: cambridge, name: "Get into Cambridge", category: .study, createdAt: at(-60, 9))]

        func habit(_ name: String, icon: String, color: HabitColor, type: HabitType, category: ItemCategory,
                   goalID: UUID? = nil, logs: [(Int, Int, Double)], note: String? = nil) -> InsightsHabit {
            let id = UUID()
            var model = Habit(id: id, name: name, frequency: .daily, type: type, createdAt: at(-90, 8), color: color, icon: icon)
            model.goalID = goalID
            let completions = logs.enumerated().map { index, log in
                Completion(habitID: id, date: at(log.0, log.1), value: log.2, note: index == 0 ? note : nil)
            }
            return InsightsHabit(habit: model, category: category, completions: completions)
        }

        let habits = [
            habit("Meditate", icon: "brain.head.profile", color: .purple, type: .binary, category: .mind,
                  logs: [(0, 7, 1), (-1, 7, 1), (-2, 8, 1), (-4, 7, 1), (-9, 7, 1), (-10, 7, 1)],
                  note: "Felt calm after"),
            habit("Drink water", icon: "drop.fill", color: .blue, type: .counter(target: 8), category: .health,
                  logs: [(0, 12, 5), (-1, 21, 8), (-2, 20, 6), (-9, 19, 8)]),
            habit("Read", icon: "book.fill", color: .orange, type: .timer(targetSeconds: 1800), category: .study,
                  goalID: cambridge, logs: [(0, 22, 1500), (-1, 22, 1800), (-4, 23, 900)]),
            habit("Run", icon: "figure.run", color: .green, type: .binary, category: .fitness,
                  logs: [(-1, 18, 1), (-4, 18, 1), (-10, 18, 1)]),
            habit("No sugar", icon: "birthday.cake", color: .red, type: .negative, category: .health,
                  logs: [(-2, 16, 1)]),
        ]

        let essay = UUID()
        let tasks = [
            InsightsTask(id: UUID(), title: "Contact professors at Cambridge", category: .study, createdAt: at(-5, 9),
                         completedAt: at(0, 10, 32), goalID: cambridge),
            InsightsTask(id: UUID(), title: "Pay the electricity bill", category: .money, createdAt: at(-3, 9),
                         completedAt: at(0, 9, 5)),
            InsightsTask(id: UUID(), title: "Weekly review", category: .work, createdAt: at(-3, 9),
                         completedAt: at(-1, 17, 40)),
            InsightsTask(id: essay, title: "Draft the personal statement", category: .study, createdAt: at(-10, 9),
                         goalID: cambridge),
            InsightsTask(id: UUID(), title: "Groceries", category: .errands, createdAt: at(-5, 9),
                         completedAt: at(-4, 11, 15)),
            InsightsTask(id: UUID(), title: "Book the dentist", category: .health, createdAt: at(-12, 9),
                         completedAt: at(-10, 14)),
            InsightsTask(id: UUID(), title: "Ship the slides", category: .work, createdAt: at(-30, 9),
                         completedAt: at(-24, 16)),
        ]

        let sessions = [
            InsightsSession(id: UUID(), session: WorkSession(startedAt: at(-2, 14), endedAt: at(-2, 15, 20)),
                            category: .study, taskID: essay),
            InsightsSession(id: UUID(), session: WorkSession(startedAt: at(0, 9, 45), endedAt: at(0, 10, 30)),
                            category: .study, taskID: tasks[0].id),
        ]

        return InsightsInput(habits: habits, tasks: tasks, sessions: sessions, goals: goals)
    }
}
