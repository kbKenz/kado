import HealthKit

extension HKWorkoutActivityType {
    /// HealthKit has no public localized name for an activity type.
    /// The common ones get a name; everything else reads "Workout".
    var displayName: String {
        switch self {
        case .running: String(localized: "Running", comment: "Workout type shown on the Calendar timeline.")
        case .walking: String(localized: "Walking", comment: "Workout type shown on the Calendar timeline.")
        case .cycling: String(localized: "Cycling", comment: "Workout type shown on the Calendar timeline.")
        case .swimming: String(localized: "Swimming", comment: "Workout type shown on the Calendar timeline.")
        case .hiking: String(localized: "Hiking", comment: "Workout type shown on the Calendar timeline.")
        case .yoga: String(localized: "Yoga", comment: "Workout type shown on the Calendar timeline.")
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            String(localized: "Strength training", comment: "Workout type shown on the Calendar timeline.")
        case .highIntensityIntervalTraining: String(localized: "HIIT", comment: "Workout type shown on the Calendar timeline.")
        case .rowing: String(localized: "Rowing", comment: "Workout type shown on the Calendar timeline.")
        case .elliptical: String(localized: "Elliptical", comment: "Workout type shown on the Calendar timeline.")
        default: String(localized: "Workout", comment: "Generic workout name shown on the Calendar timeline.")
        }
    }
}
