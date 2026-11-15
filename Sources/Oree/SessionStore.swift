import AppKit
import Observation

@Observable
final class SessionStore {
    private(set) var sessions: [AgentSession] = []
    let preferences = Preferences()
    let role = DesktopRole()
    let agents = AgentCheck()
    let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    @ObservationIgnored private var folders: [URL: FolderModel] = [:]
    let reminders = RemindersFeed()
    let calendar = CalendarFeed()
    let mail = MailFeed()
    let playing = NowPlaying()
    let weather = WeatherFeed()
    let batteries = BatteryFeed()
    let focus = FocusTimer()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var saver: Timer?
    /// What was last written, so an unchanged history is not written again.
    @ObservationIgnored private var saved = Data()

    /// Where conversations are kept between launches.
    private static let history = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Oree", isDirectory: true)
        .appendingPathComponent("conversations.json")

    init() {
        guard !Demo.on else { return }
        let preferences = preferences
        if let data = try? Data(contentsOf: Self.history),
           let records = try? JSONDecoder().decode([AgentSession.Record].self, from: data) {
            sessions = records.map { AgentSession(record: $0, bypass: { preferences.bypassPermissions }) }
            saved = data
        }
        // A conversation is written down within moments of changing.
        saver = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.save() }
    }

    /// Keep the latest conversations, those with anything in them.
    func save() {
        guard !Demo.on else { return }
        let records = sessions.filter { !$0.entries.isEmpty }.prefix(30).map(\.record)
        guard let data = try? JSONEncoder().encode(Array(records)), data != saved else { return }
        try? FileManager.default.createDirectory(at: Self.history.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.history, options: .atomic)
        saved = data
    }

    /// Read everything the desktop's widgets show, now and once a minute.
    /// Each feed reads its own source, so nothing depends on the other app
    /// being open.
    func keepFresh() {
        refreshFeeds()
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshFeeds()
        }
    }

    /// Put every question macOS has to ask at once, so setting up is the
    /// only time it asks.
    func askPermissions() {
        refreshFeeds()
    }

    private func refreshFeeds() {
        reminders.refresh()
        calendar.refresh()
        mail.refresh()
        batteries.refresh()
        weather.refresh()
    }

    /// Every tool call any agent is waiting on, oldest session first.
    var waiting: [(session: AgentSession, approval: AgentSession.Approval)] {
        sessions.reversed().flatMap { session in
            session.approvals.map { (session, $0) }
        }
    }

    /// The model for a folder, made the first time it is shown.
    func folder(_ url: URL) -> FolderModel {
        if let known = folders[url] { return known }
        let model = FolderModel(url: url)
        folders[url] = model
        return model
    }

    /// The folders on offer: the Desktop itself, then the pinned.
    var roots: [URL] {
        (preferences.showsFiles ? [desktopURL] : []) + preferences.pinned.filter { $0 != desktopURL }
    }

    /// Start an agent on a task on this Mac, about the selected items when
    /// there are any.
    @discardableResult
    func start(_ task: String, about items: [URL]) -> AgentSession {
        let preferences = preferences
        let session = AgentSession(
            agent: preferences.agent,
            folder: FileManager.default.homeDirectoryForCurrentUser,
            bypass: { preferences.bypassPermissions }
        )
        sessions.insert(session, at: 0)
        var message = task
        if !items.isEmpty {
            message += "\n\nSelected items:\n" + items.map(\.path).joined(separator: "\n")
        }
        session.send(message, shownAs: task)
        return session
    }

    func stopAll() {
        save()
        sessions.forEach { $0.stop() }
    }
}
