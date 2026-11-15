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
        if Demo.on {
            access = .granted
            items = [("Renew the passport", 3), ("Send the invoice", 5), ("Water the plants", nil)].map { title, days in
                Item(id: title, title: title, due: days.map { Demo.at(9, 0, daysOn: $0) }, reminder: EKReminder(eventStore: events))
            }
            return
        }
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

    /// A new reminder in the default list, with nothing but its title.
    func add(_ title: String) {
        if Demo.on {
            items.insert(Item(id: UUID().uuidString, title: title, due: nil, reminder: EKReminder(eventStore: events)), at: 0)
            return
        }
        let reminder = EKReminder(eventStore: events)
        reminder.title = title
        reminder.calendar = events.defaultCalendarForNewReminders()
        try? events.save(reminder, commit: true)
        refresh()
    }

    func complete(_ item: Item) {
        item.reminder.isCompleted = true
        try? events.save(item.reminder, commit: true)
        refresh()
    }
}

struct RemindersWidget: View {
    let feed: RemindersFeed
    /// A new one is being written at the top of the list.
    @State private var adding = false
    @State private var draft = ""
    @FocusState private var writing: Bool

    var body: some View {
        Widget(
            title: "Reminders", icon: .checklist, count: feed.items.count, height: widgetHeight,
            accessory: feed.access == .granted ? AnyView(addButton) : nil
        ) {
            switch feed.access {
            case .unasked:
                Hint("Reading your reminders…")
            case .denied:
                Hint("Allow Oree to see Reminders in System Settings, under Privacy & Security.")
            case .granted:
                VStack(spacing: 2) {
                    if adding {
                        newReminder
                    } else if feed.items.isEmpty {
                        Hint("Nothing left to do.")
                    }
                    ForEach(feed.items.prefix(adding ? 4 : 5)) { item in
                        // Centred, so the round box sits level with the text.
                        HStack(alignment: .center, spacing: 8) {
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
        .onChange(of: writing) { _, focused in
            // Leaving the field closes it, unless something is half written.
            if !focused, draft.trimmingCharacters(in: .whitespaces).isEmpty { adding = false }
        }
    }

    private var addButton: some View {
        Button {
            adding = true
            writing = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New reminder")
    }

    /// A line to write a reminder on, as plain as a to-do list: Return adds
    /// it and leaves the line ready for the next, Escape puts it away.
    private var newReminder: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .strokeBorder(Theme.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .frame(width: 13, height: 13)
            TextField("New reminder", text: $draft)
                .textFieldStyle(.plain)
                .focused($writing)
                .onSubmit {
                    let title = draft.trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty { feed.add(title) }
                    draft = ""
                    writing = true
                }
                .onExitCommand {
                    draft = ""
                    adding = false
                }
        }
        .padding(.vertical, 5)
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

    /// The two weeks shown: from the first day of this week, fourteen days.
    static var fortnight: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        return (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        if Demo.on {
            access = .granted
            events = [
                Event(id: "a", title: "Design review", start: Demo.at(10, 30), allDay: false, colour: .orange),
                Event(id: "b", title: "Lunch at the harbour", start: Demo.at(13, 0), allDay: false, colour: .blue),
                Event(id: "c", title: "Flight to Lisbon", start: Demo.at(7, 15, daysOn: 1), allDay: false, colour: .green),
            ]
            return
        }
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
            case .granted:
                VStack(alignment: .leading, spacing: 8) {
                    fortnight
                    // A short rule between the days and what is on them.
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 120, height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    if feed.events.isEmpty {
                        Text("Nothing on today or tomorrow.")
                            .font(.callout)
                            .foregroundStyle(Theme.secondary)
                    }
                    ForEach(feed.events.prefix(3)) { event in
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
                        .padding(.vertical, 1)
                    }
                }
            }
        }
        // A click anywhere on it opens Calendar.
        .contentShape(Rectangle())
        .onTapGesture {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        }
        .help("Open Calendar")
    }

    /// Two weeks as a calendar does them: the days of the week across the
    /// top, and today ringed with a dashed line.
    private var fortnight: some View {
        let calendar = Calendar.current
        let days = CalendarFeed.fortnight
        let letters = days.prefix(7).map { calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: $0) - 1] }
        // Fixed columns spread edge to edge, drawn a little past the card's
        // padding so the first letter lines up with the title's icon.
        func row<Cell: View>(_ cells: [Cell]) -> some View {
            HStack(spacing: 0) {
                ForEach(cells.indices, id: \.self) { index in
                    if index > 0 { Spacer(minLength: 0) }
                    cells[index].frame(width: 24)
                }
            }
        }
        return VStack(spacing: 3) {
            row(letters.map { letter in
                Text(letter)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.secondary)
            })
            ForEach(0..<2, id: \.self) { week in
                row(days[(week * 7)..<(week * 7 + 7)].map { day in
                    let today = calendar.isDateInToday(day)
                    let past = day < calendar.startOfDay(for: Date())
                    return Text("\(calendar.component(.day, from: day))")
                        .font(.caption.weight(today ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(today ? Theme.accent : past ? Theme.secondary : Theme.primary)
                        .frame(width: 24, height: 19)
                        .overlay {
                            if today {
                                Capsule().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2]))
                            }
                        }
                })
            }
        }
        .padding(.horizontal, -6)
    }

    /// "14:30", "All day", and "Tomorrow" in front of either when it is.
    private func when(_ event: CalendarFeed.Event) -> String {
        let time = event.allDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened)
        // An event already under way began before today's first minute or today.
        return Calendar.current.isDateInTomorrow(event.start) ? "Tomorrow · \(time)" : time
    }
}
