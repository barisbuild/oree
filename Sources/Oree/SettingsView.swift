import CoreLocation
import EventKit
import SwiftUI

/// What macOS has decided about each thing Oree may ask to see.
enum Access {
    enum Answer { case unasked, allowed, refused }

    struct Item: Identifiable {
        let name: String
        let purpose: String
        let icon: Icon
        let answer: Answer
        /// The page of Privacy & Security where it is changed.
        let pane: String
        var id: String { name }
    }

    static func read() -> [Item] {
        func answer(_ status: EKAuthorizationStatus) -> Answer {
            switch status {
            case .notDetermined: .unasked
            case .fullAccess, .authorized: .allowed
            default: .refused
            }
        }
        let location: Answer = switch CLLocationManager().authorizationStatus {
        case .notDetermined: .unasked
        case .denied, .restricted: .refused
        default: .allowed
        }
        return [
            Item(name: "Calendar", purpose: "Today's and tomorrow's events.", icon: .calendar,
                 answer: answer(EKEventStore.authorizationStatus(for: .event)), pane: "Privacy_Calendars"),
            Item(name: "Reminders", purpose: "Your open reminders.", icon: .checklist,
                 answer: answer(EKEventStore.authorizationStatus(for: .reminder)), pane: "Privacy_Reminders"),
            Item(name: "Location", purpose: "The weather where you are, from a rounded position.", icon: .sunCloud,
                 answer: location, pane: "Privacy_LocationServices"),
        ]
    }

    /// Full Disk Access shows as being able to look where it alone lets an app look.
    static var hasFullDisk: Bool {
        ["Library/Safari", "Library/Mail", "Library/Messages"].contains { folder in
            (try? FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory() + "/" + folder)) != nil
        }
    }

    static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Settings: a list of pages on the left, the chosen page on the right.
struct SettingsCard: View {
    let store: SessionStore
    let done: () -> Void

    private enum Page: String, CaseIterable, Identifiable {
        case general = "General"
        case agents = "Agents"
        case desktop = "Desktop"
        case access = "Access"

        var id: Self { self }
        var icon: Icon {
            switch self {
            case .general: .settings
            case .agents: .activity
            case .desktop: .computer
            case .access: .checkCircle
            }
        }
    }

    @State private var page = Page.general
    @Namespace private var marker

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: done)

            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch page {
                        case .general: GeneralPage(preferences: store.preferences)
                        case .agents: AgentsPage(preferences: store.preferences, check: store.agents)
                        case .desktop: DesktopPage(preferences: store.preferences, role: store.role)
                        case .access: AccessPage(ask: store.askPermissions)
                        }
                    }
                    .padding(26)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .transition(.opacity)
                    .id(page)
                }
                .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
            }
            .frame(width: 820, height: 540)
            .card()
            .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
            // Clicks on the card are the card's, not the backdrop's.
            .onTapGesture {}
        }
        .font(.callout)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            ForEach(Page.allCases) { each in
                Button {
                    withAnimation(.smooth(duration: 0.25)) { page = each }
                } label: {
                    HStack(spacing: 10) {
                        IconView(each.icon, size: 17)
                        Text(each.rawValue)
                        Spacer()
                    }
                    .foregroundStyle(page == each ? Theme.primary : Theme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background {
                        if page == each {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Theme.panel)
                                .matchedGeometryEffect(id: "page", in: marker)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button("Done", action: done)
                .buttonStyle(.plain)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.ground)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Theme.ink.opacity(0.95), in: Capsule())
                .keyboardShortcut(.cancelAction)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 22)
        .frame(width: 200)
    }
}

// MARK: Building blocks

private struct PageTitle: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(detail)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 16)
    }
}

/// Rows that belong together, on one panel, with hairlines between them.
private struct Panel<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .kerning(0.6)
                    .foregroundStyle(Theme.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content
            }
            .background(Theme.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
        }
        .padding(.bottom, 18)
    }
}

/// An icon, a name and a line about it on the left; whatever acts on it on
/// the right.
private struct Row<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var icon: Icon? = nil
    var isLast = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon {
                    IconView(icon, size: 17)
                        .frame(width: 32, height: 32)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            if !isLast {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
                    .padding(.leading, icon == nil ? 14 : 58)
            }
        }
    }
}

/// A switch with no label of its own; its row says what it is.
private struct Switch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
    }
}

/// "Allowed", "Not signed in": a state in a word, coloured by how it stands.
private struct Badge: View {
    enum Tone { case good, warn, quiet }
    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tone == .good ? Color.green : tone == .warn ? .orange : Theme.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                (tone == .good ? Color.green : tone == .warn ? .orange : Theme.ink).opacity(0.12),
                in: Capsule()
            )
    }
}

// MARK: Pages

private struct GeneralPage: View {
    @Bindable var preferences: Preferences

    var body: some View {
        PageTitle(title: "General", detail: "The picture across the top of your desktop.")
        Panel(title: "Picture") {
            Row(
                title: preferences.wallpaperPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "System wallpaper",
                detail: preferences.wallpaperPath == nil ? "Follows whatever your Mac's wallpaper is." : "Chosen by you.",
                icon: .image
            ) {
                HStack {
                    if preferences.wallpaperPath != nil {
                        Button("Use system") { preferences.wallpaperPath = nil }
                    }
                    Button("Choose…", action: preferences.chooseWallpaper)
                }
            }
            Row(
                title: "Size",
                detail: preferences.pictureFills
                    ? "The whole screen, with the widgets as glass over it."
                    : "Across the top, fading into the desktop.",
                isLast: true
            ) {
                Picker("", selection: $preferences.pictureFills) {
                    Text("At the top").tag(false)
                    Text("Full screen").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

}

private struct AgentsPage: View {
    @Bindable var preferences: Preferences
    let check: AgentCheck

    var body: some View {
        PageTitle(
            title: "Agents",
            detail: "Oree works through the command-line agents on this Mac, signed in with your own account. It never sees or keeps a key."
        )
        Panel(title: "Use") {
            ForEach(Agent.allCases) { agent in
                let status = check.status(of: agent)
                Row(
                    title: agent.name,
                    detail: agent == .claude
                        ? "Asks you before it changes a file or runs a command."
                        : "Reads around the Mac but cannot change anything, since it has no way to ask first.",
                    icon: agent == .claude ? .activity : .code,
                    isLast: agent == Agent.allCases.last
                ) {
                    HStack(spacing: 10) {
                        if check.checking && check.statuses.isEmpty {
                            ProgressView().controlSize(.small)
                        } else if !status.installed {
                            Badge(text: "Not installed", tone: .warn)
                            Button("Install") { check.runInTerminal(agent.install) }
                        } else if !status.signedIn {
                            Badge(text: "Not signed in", tone: .warn)
                            Button("Sign in") { check.runInTerminal(agent.signIn) }
                        } else {
                            Badge(text: "Ready", tone: .good)
                        }
                        Switch(isOn: use(agent))
                    }
                }
            }
        }
        if preferences.agents.count > 1 {
            Panel {
                Row(title: "New tasks go to", detail: "Change it for one task from the task box.", isLast: true) {
                    Picker("", selection: $preferences.agent) {
                        ForEach(Agent.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }
            }
        }
        Button("Check again", action: check.refresh)
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondary)
            .task { check.refresh() }
    }

    /// One agent always stays on.
    private func use(_ agent: Agent) -> Binding<Bool> {
        Binding(
            get: { preferences.agents.contains(agent) },
            set: { on in
                if on {
                    preferences.agents.insert(agent)
                } else if preferences.agents.count > 1 {
                    preferences.agents.remove(agent)
                }
            }
        )
    }
}

private struct DesktopPage: View {
    @Bindable var preferences: Preferences
    let role: DesktopRole

    var body: some View {
        PageTitle(title: "Desktop", detail: "Oree's place on this Mac, and the folders it keeps to hand.")
        Panel(title: "Role") {
            Row(
                title: "Be my desktop",
                detail: role.problem ?? "Opens when you log in and takes the place of Finder's desktop. Other apps use Finder windows for files and folders.",
                icon: .computer,
                isLast: true
            ) {
                if role.isOn {
                    HStack(spacing: 10) {
                        Badge(text: "On", tone: .good)
                        Button("Give back to Finder", action: role.turnOff)
                    }
                } else {
                    Button("Turn on", action: role.turnOn)
                }
            }
        }
        Panel(title: "Files") {
            Row(title: "Show my Desktop folder", icon: .folder) {
                Switch(isOn: $preferences.showsFiles)
            }
            Row(title: "Gather items into stacks", detail: "One pile per kind inside an open folder.", icon: .layers, isLast: true) {
                Switch(isOn: $preferences.stacks)
            }
        }
        Panel(title: "Pinned folders") {
            ForEach(preferences.pinned, id: \.self) { folder in
                Row(title: FileManager.default.displayName(atPath: folder.path), detail: folder.path, icon: .folder) {
                    Button {
                        preferences.pinned.removeAll { $0 == folder }
                    } label: {
                        IconView(.cancel, size: 13)
                            .foregroundStyle(Theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Unpin")
                }
            }
            Row(title: "Pin a folder", icon: .folderAdd, isLast: true) {
                Button("Choose…", action: preferences.pinFolder)
            }
        }
    }
}

private struct AccessPage: View {
    let ask: () -> Void
    @State private var items = Access.read()
    @State private var hasFullDisk = Access.hasFullDisk

    var body: some View {
        PageTitle(
            title: "Access",
            detail: "macOS asks once for each and remembers. Nothing leaves this Mac except a rounded location, for the weather."
        )
        Panel(title: "Widgets") {
            ForEach(items) { item in
                Row(title: item.name, detail: item.purpose, icon: item.icon, isLast: item.id == items.last?.id) {
                    switch item.answer {
                    case .allowed:
                        Badge(text: "Allowed", tone: .good)
                    case .unasked:
                        // macOS puts its own question when this is pressed.
                        Button("Allow", action: ask)
                    case .refused:
                        HStack(spacing: 10) {
                            Badge(text: "Refused", tone: .warn)
                            Button("Open Settings") { Access.openSettings(item.pane) }
                        }
                    }
                }
            }
        }
        Panel(title: "Optional") {
            Row(
                title: "Full Disk Access",
                detail: hasFullDisk
                    ? "Folders never ask, and your mail shows with Mail closed."
                    : "Without it each folder asks once when you first open it, and mail shows only while Mail is open.",
                icon: .folder,
                isLast: true
            ) {
                if hasFullDisk {
                    Badge(text: "Allowed", tone: .good)
                } else {
                    Button("Open Settings") { Access.openSettings("Privacy_AllFiles") }
                }
            }
        }
        // The answers change in System Settings and in macOS's own dialogs.
        .task {
            while !Task.isCancelled {
                items = Access.read()
                hasFullDisk = Access.hasFullDisk
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
