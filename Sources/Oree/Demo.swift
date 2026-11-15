import Foundation

/// Made-up data in place of the user's own, for recording the app without
/// showing anyone's calendar, mail or files:
/// `defaults write space.oree.app demo -bool true`, then relaunch.
enum Demo {
    static let on = UserDefaults.standard.bool(forKey: "demo")

    /// A time today, or a number of days on, at an hour and minute.
    static func at(_ hour: Int, _ minute: Int, daysOn: Int = 0) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: daysOn, to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
