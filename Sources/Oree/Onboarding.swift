import CoreLocation
import EventKit
import SwiftUI

/// The first launch: an opening, then the few choices that shape the
/// desktop, one at a time.
struct Onboarding: View {
    let store: SessionStore
    let done: () -> Void

    private enum Step: Int, CaseIterable {
        case opening, agents, access, desktop
    }

    @State private var step = Step.opening
    @State private var forward = true
    @State private var frames = FrameBox()

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            DotField()
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Group {
                    switch step {
                    case .opening: Opening { go(.agents) }
                    case .agents: AgentsStep(preferences: store.preferences, check: store.agents)
                    case .access: AccessStep(ask: store.askPermissions)
                    case .desktop: DesktopStep(preferences: store.preferences, role: store.role)
                    }
                }
                .transition(.asymmetric(
                    insertion: AnyTransition.offset(x: forward ? 40 : -40).combined(with: .opacity),
                    removal: AnyTransition.offset(x: forward ? -40 : 40).combined(with: .opacity)
                ))
                .id(step)

                // Right under the choices, so the way on is where the eye is.
                if step != .opening {
                    footer
                }
            }
            .frame(maxWidth: 560)
        }
        // It is still a desktop: dragging across it draws the selection
        // rectangle, though there is nothing here to pick yet.
        .modifier(Sweep(picked: .constant([]), frames: frames))
    }

    private var footer: some View {
        HStack {
            Button("Back") { go(Step(rawValue: step.rawValue - 1) ?? .opening) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
            Spacer()
            // Where you are among the steps.
            HStack(spacing: 6) {
                ForEach(Step.allCases.dropFirst(), id: \.self) { each in
                    Capsule()
                        .fill(each == step ? Theme.accent : Theme.panel)
                        .frame(width: each == step ? 18 : 6, height: 6)
                }
            }
            .animation(.smooth(duration: 0.3), value: step)
            Spacer()
            Button(step == .desktop ? "Open my desktop" : "Continue") {
                if let next = Step(rawValue: step.rawValue + 1) {
                    go(next)
                } else {
                    done()
                }
            }
            .buttonStyle(Prominent())
            .keyboardShortcut(.defaultAction)
        }
    }

    private func go(_ next: Step) {
        forward = next.rawValue > step.rawValue
        withAnimation(.smooth(duration: 0.45)) { step = next }
    }
}

/// The button that moves things on.
private struct Prominent: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: The opening

/// A field of dots that a wave of light crosses once, from the middle out,
/// and then leaves faintly lit. It draws only while the wave is moving.
private struct DotField: View {
    @State private var began = Date()
    @State private var settled = false

    private static let spacing: CGFloat = 16
    private static let length: TimeInterval = 3.2

    var body: some View {
        TimelineView(.animation(paused: settled)) { moment in
            let elapsed = moment.date.timeIntervalSince(began)
            Canvas { context, size in
                let ink = Theme.accent
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let reach = hypot(size.width, size.height) / 2
                // The wave's front, easing out as it nears the corners.
                let progress = min(1, elapsed / Self.length)
                let front = reach * (1 - pow(1 - progress, 3)) * 1.15
                for row in 0...Int(size.height / Self.spacing) {
                    for column in 0...Int(size.width / Self.spacing) {
                        let point = CGPoint(x: CGFloat(column) * Self.spacing, y: CGFloat(row) * Self.spacing)
                        let distance = hypot(point.x - centre.x, point.y - centre.y)
                        guard distance < front else { continue }
                        // Bright at the front, settling to a faint glow behind
                        // it that falls away toward the edges.
                        let behind = (front - distance) / 220
                        let crest = max(0, 1 - behind)
                        let rest = 0.2 * (1 - distance / reach)
                        let light = rest + 0.75 * crest * crest
                        let radius = 1.1 + 1.5 * crest
                        context.fill(
                            Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(ink.opacity(light))
                        )
                    }
                }
            }
            .onChange(of: elapsed > Self.length + 1.6) { _, over in
                if over { settled = true }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The name arriving a letter at a time, then what it is, then the way in.
private struct Opening: View {
    let begin: () -> Void
    @State private var shown = 0
    @State private var showsLine = false
    @State private var showsButton = false

    private static let name = Array("Oree")
    private static let mark = Bundle.main.url(forResource: "Mark", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        VStack(spacing: 18) {
            // The mark first, then the name beside it a letter at a time.
            HStack(spacing: 18) {
                if let mark = Self.mark {
                    Image(nsImage: mark)
                        .resizable()
                        .frame(width: 78, height: 78)
                        .opacity(shown > 0 ? 1 : 0)
                        .scaleEffect(shown > 0 ? 1 : 0.6)
                        .rotationEffect(.degrees(shown > 0 ? 0 : -90))
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: shown > 0)
                }
            HStack(spacing: 2) {
                ForEach(Self.name.indices, id: \.self) { index in
                    Text(String(Self.name[index]))
                        .font(.system(size: 88, weight: .semibold, design: .rounded))
                        .opacity(index < shown ? 1 : 0)
                        .blur(radius: index < shown ? 0 : 14)
                        .offset(y: index < shown ? 0 : 18)
                        .animation(.spring(response: 0.7, dampingFraction: 0.78), value: shown)
                }
            }
            }
            (Text("Your desktop, ").foregroundStyle(Theme.secondary) + Text("put to work.").foregroundStyle(Theme.accent))
                .font(.title3.weight(.medium))
                .opacity(showsLine ? 1 : 0)
                .offset(y: showsLine ? 0 : 8)
            Button("Get started", action: begin)
                .buttonStyle(Prominent())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 18)
                .opacity(showsButton ? 1 : 0)
                .offset(y: showsButton ? 0 : 8)
                .disabled(!showsButton)
        }
        .task {
            // The wave has to be on its way before the name lands in it.
            try? await Task.sleep(for: .milliseconds(700))
            for count in 1...Self.name.count {
                shown = count
                try? await Task.sleep(for: .milliseconds(110))
            }
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.smooth(duration: 0.6)) { showsLine = true }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.smooth(duration: 0.6)) { showsButton = true }
        }
    }
}

// MARK: The steps

private struct StepHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 30, weight: .semibold))
            Text(detail)
                .font(.body)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 10)
    }
}

/// A choice among a few, shown as a card.
private struct Choice<Trailing: View>: View {
    let title: String
    let detail: String
    let icon: Icon
    let chosen: Bool
    let action: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconView(icon, size: 22)
                    .frame(width: 44, height: 44)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(14)
            .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(chosen ? 0.9 : 0), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: chosen)
    }
}

/// The mark on the right of a choice that can be on together with others.
private struct Check: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.ink.opacity(isOn ? 0 : 0.3), lineWidth: 1.5)
            if isOn {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.ground)
            }
        }
        .frame(width: 22, height: 22)
        .animation(.smooth(duration: 0.2), value: isOn)
    }
}

private struct AgentsStep: View {
    let preferences: Preferences
    let check: AgentCheck

    var body: some View {
        VStack(spacing: 12) {
            StepHeader(
                title: "Choose your agents",
                detail: "Pick one or both. Oree works through the command-line agents you already have, signed in with your own account. It never sees or keeps a key."
            )
            ForEach(Agent.allCases) { agent in
                let status = check.status(of: agent)
                Choice(
                    title: agent.name,
                    detail: detail(for: agent, status),
                    icon: agent == .claude ? .activity : .code,
                    chosen: preferences.agents.contains(agent),
                    action: { toggle(agent) }
                ) {
                    HStack(spacing: 10) {
                        if check.checking && check.statuses.isEmpty {
                            ProgressView().controlSize(.small)
                        } else if !status.installed {
                            Button("Install") { check.runInTerminal(agent.install) }
                        } else if !status.signedIn {
                            Button("Sign in") { check.runInTerminal(agent.signIn) }
                        }
                        Check(isOn: preferences.agents.contains(agent))
                    }
                }
            }
            Button("Check again", action: check.refresh)
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .task { check.refresh() }
    }

    /// One always stays on.
    private func toggle(_ agent: Agent) {
        if !preferences.agents.contains(agent) {
            preferences.agents.insert(agent)
        } else if preferences.agents.count > 1 {
            preferences.agents.remove(agent)
        }
    }

    private func detail(for agent: Agent, _ status: AgentCheck.Status) -> String {
        if !status.installed { return "Not installed. Install opens Terminal and runs the installer." }
        if !status.signedIn { return "Installed, not signed in. Sign in opens Terminal for you." }
        return agent == .claude
            ? "Signed in. Asks you before it changes a file or runs a command."
            : "Signed in. Works inside the folder you give it; around the Mac it can read but not change things."
    }
}

private struct AccessStep: View {
    let ask: () -> Void
    /// What macOS says about each permission right now.
    @State private var states = AccessStep.read()

    private enum Answer { case unasked, allowed, refused }

    private static func read() -> [(name: String, answer: Answer)] {
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
            ("Calendar", answer(EKEventStore.authorizationStatus(for: .event))),
            ("Reminders", answer(EKEventStore.authorizationStatus(for: .reminder))),
            ("Location", location),
        ]
    }

    @State private var hasFullAccess = AccessStep.readsProtectedFiles

    /// Full Disk Access shows as being able to look where it alone lets an app look.
    private static var readsProtectedFiles: Bool {
        // Folders macOS keeps closed to every app without Full Disk Access.
        ["Library/Safari", "Library/Mail", "Library/Messages"].contains { folder in
            (try? FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory() + "/" + folder)) != nil
        }
    }

    var body: some View {
        let unasked = states.contains { $0.answer == .unasked }
        let refused = states.filter { $0.answer == .refused }.map(\.name)
        VStack(spacing: 12) {
            StepHeader(
                title: "Let it see what it shows",
                detail: "macOS asks once for each and remembers. Nothing leaves this Mac except a rounded location, for the weather."
            )
            Choice(
                title: "Calendar, reminders and location",
                detail: unasked
                    ? "For the Calendar, Reminders and Weather widgets. macOS will ask for each."
                    : refused.isEmpty
                        ? "Allowed. macOS has nothing left to ask."
                        : "\(refused.joined(separator: " and ")) was refused earlier. macOS will not ask twice; turn it on in Privacy & Security.",
                icon: .calendar,
                chosen: false,
                action: {}
            ) {
                if unasked {
                    Button("Allow", action: ask)
                } else if refused.isEmpty {
                    IconView(.checkCircle, size: 20)
                        .foregroundStyle(.green)
                } else {
                    Button("Open Settings") { openSettings("Privacy") }
                }
            }
            Choice(
                title: "Full Disk Access · optional",
                detail: hasFullAccess
                    ? "Allowed. Folders never ask, and your mail shows with Mail closed."
                    : "Skip it and each folder simply asks once when you first open it. Turn it on only if you want mail shown while Mail is closed.",
                icon: .folder,
                chosen: false,
                action: {}
            ) {
                if hasFullAccess {
                    IconView(.checkCircle, size: 20)
                        .foregroundStyle(.green)
                } else {
                    Button("Open Settings") { openSettings("Privacy_AllFiles") }
                }
            }
        }
        // The answers change in System Settings and in macOS's own dialogs.
        .task {
            while !Task.isCancelled {
                states = Self.read()
                hasFullAccess = Self.readsProtectedFiles
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct DesktopStep: View {
    let preferences: Preferences
    let role: DesktopRole

    var body: some View {
        VStack(spacing: 12) {
            StepHeader(
                title: "Make it your desktop",
                detail: "Both can be changed later in Settings."
            )
            Choice(
                title: "Be my desktop",
                detail: role.problem ?? "Oree opens when you log in and takes the place of Finder's desktop. Other apps use Finder windows for files and folders.",
                icon: .computer,
                chosen: role.isOn,
                action: { if !role.isOn { role.turnOn() } }
            ) {
                if role.isOn {
                    IconView(.checkCircle, size: 20)
                        .foregroundStyle(.green)
                } else {
                    Button("Turn on", action: role.turnOn)
                }
            }
            Choice(
                title: "Picture",
                detail: preferences.wallpaperPath.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? "Following your system wallpaper.",
                icon: .image,
                chosen: false,
                action: preferences.chooseWallpaper
            ) {
                Button("Choose", action: preferences.chooseWallpaper)
            }
        }
    }
}
