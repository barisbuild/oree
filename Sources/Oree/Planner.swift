import EventKit
import Observation
import SwiftUI

enum FeedAccess { case unasked, denied, granted }

/// The user's open reminders, soonest first. Read from the system's own
/// store, so the Reminders app need not be open.
@Observable
final class RemindersFeed {
    struct Item: Identifiable {
        let id: String
        let title: String
        let due: Date?
        fileprivate let reminder: EKReminder
    }

    private(set) var items: [Item] = []
    private(set) var access = FeedAccess.unasked
    @ObservationIgnored private let events = EKEventStore()

    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: events, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        events.requestFullAccessToReminders { [weak self] granted, _ in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async { self.access = .denied }
                return
            }
            let open = self.events.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: nil
            )
            self.events.fetchReminders(matching: open) { found in
                let items = (found ?? [])
                    .map { reminder in
                        Item(
                            id: reminder.calendarItemIdentifier,
                            title: reminder.title ?? "",
                            due: reminder.dueDateComponents.flatMap(Calendar.current.date(from:)),
                            reminder: reminder
                        )
                    }
                    // Dated ones by date; the undated after them.
                    .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                DispatchQueue.main.async {
                    self.access = .granted
                    self.items = Array(items.prefix(5))
                }
            }
        }
    }

    func complete(_ item: Item) {
        item.reminder.isCompleted = true
        try? events.save(item.reminder, commit: true)
        refresh()
    }
}

struct RemindersWidget: View {
    let feed: RemindersFeed

    var body: some View {
        Widget(title: "Reminders", icon: .checklist, count: feed.items.count, height: widgetHeight) {
            switch feed.access {
            case .unasked:
                Hint("Reading your reminders…")
            case .denied:
                Hint("Allow Oree to see Reminders in System Settings, under Privacy & Security.")
            case .granted where feed.items.isEmpty:
                Hint("Nothing left to do.")
            case .granted:
                VStack(spacing: 2) {
                    ForEach(feed.items) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Button {
                                feed.complete(item)
                            } label: {
                                Circle()
                                    .strokeBorder(Theme.secondary, lineWidth: 1.5)
                                    .frame(width: 13, height: 13)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Mark as done")
                            Text(item.title)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if let due = item.due {
                                Text(due, format: .dateTime.day().month(.abbreviated))
                                    .font(.caption)
                                    .foregroundStyle(due < Date() ? .orange : Theme.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }
}

/// What is on the calendar from now to the end of tomorrow.
@Observable
final class CalendarFeed {
    struct Event: Identifiable {
        let id: String
        let title: String
        let start: Date
        let allDay: Bool
        let colour: Color
    }

    private(set) var events: [Event] = []
    private(set) var access = FeedAccess.unasked
    @ObservationIgnored private let store = EKEventStore()

    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async { self.access = .denied }
                return
            }
            let calendar = Calendar.current
            let now = Date()
            let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) ?? now
            let found = self.store.events(matching: self.store.predicateForEvents(
                withStart: now, end: end, calendars: nil
            ))
            let events = found
                .sorted { $0.startDate < $1.startDate }
                .prefix(5)
                .map { event in
                    Event(
                        id: (event.eventIdentifier ?? event.title) + "\(event.startDate.timeIntervalSince1970)",
                        title: event.title ?? "",
                        start: event.startDate,
                        allDay: event.isAllDay,
                        colour: Color(cgColor: event.calendar.cgColor)
                    )
                }
            DispatchQueue.main.async {
                self.access = .granted
                self.events = Array(events)
            }
        }
    }
}

struct CalendarWidget: View {
    let feed: CalendarFeed

    var body: some View {
        Widget(title: "Calendar", icon: .calendar, count: feed.events.count, height: widgetHeight) {
            switch feed.access {
            case .unasked:
                Hint("Reading your calendar…")
            case .denied:
                Hint("Allow Oree to see Calendars in System Settings, under Privacy & Security.")
            case .granted where feed.events.isEmpty:
                Hint("Nothing on today or tomorrow.")
            case .granted:
                VStack(spacing: 2) {
                    ForEach(feed.events) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(event.colour)
                                .frame(width: 3, height: 13)
                            Text(event.title)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(when(event))
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    /// "14:30", "All day", and "Tomorrow" in front of either when it is.
    private func when(_ event: CalendarFeed.Event) -> String {
        let time = event.allDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened)
        // An event already under way began before today's first minute or today.
        return Calendar.current.isDateInTomorrow(event.start) ? "Tomorrow · \(time)" : time
    }
}
