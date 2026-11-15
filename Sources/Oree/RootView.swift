import SwiftUI

/// How much of the screen the picture takes, from the top.
private let heroShare: CGFloat = 0.46

struct RootView: View {
    let store: SessionStore
    let space: ScreenSpace
    @State private var showsSettings = false

    var body: some View {
        ZStack {
            HomeView(store: store, insets: space.insets) {
                showsSettings = true
            }
            if !store.preferences.onboarded {
                Onboarding(store: store) {
                    withAnimation(.smooth(duration: 0.7)) { store.preferences.onboarded = true }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else if showsSettings {
                SettingsCard(store: store) {
                    showsSettings = false
                }
            }
        }
    }
}

struct HomeView: View {
    let store: SessionStore
    let insets: EdgeInsets
    let settings: () -> Void
    /// The files picked on this display.
    @State private var picked: Set<URL> = []
    /// Where each visible file icon is, for the sweep to test against.
    @State private var frames = FrameBox()
    /// The conversation open on this display. Each display keeps its own:
    /// one can stay on the widgets while another follows an agent.
    @State private var chat: AgentSession.ID?

    var body: some View {
        let preferences = store.preferences
        let session = store.sessions.first { $0.id == chat }
        GeometryReader { geometry in
            let heroHeight = geometry.size.height * heroShare
            // The picture stays where it is whatever is in front of it.
            ZStack(alignment: .top) {
                HeroView(imageURL: preferences.wallpaperURL)
                    .frame(height: heroHeight)

                VStack(spacing: 28) {
                    Composer(store: store, picked: picked, open: open)
                        .frame(maxWidth: 600)
                    DesktopView(store: store, picked: $picked, frames: frames, open: open)
                        .frame(maxWidth: 1320)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.top, heroHeight - 96)
                .padding(.horizontal, 24)
                .padding(.bottom, insets.bottom + 28)
                .opacity(session == nil ? 1 : 0)
                // Out of reach while a conversation is up, and unable to hold
                // the keyboard: two fields wanting it would fight over it.
                .disabled(session != nil)

                // A conversation takes the desktop's place, not a window's:
                // it runs over the picture, which shows through.
                if let session {
                    ChatView(session: session, insets: insets) { show(nil) }
                        .id(session.id)
                        .transition(.opacity)
                }
            }
            .frame(height: geometry.size.height)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    CornerButton(title: "Wallpaper", icon: .image, action: preferences.chooseWallpaper)
                    CornerButton(title: "Settings", icon: .settings, action: settings)
                }
                .padding(.top, insets.top + 12)
                .padding(.trailing, insets.trailing + 16)
            }
        }
        // The sweep works anywhere on the desktop, picture included, the way
        // it does on Finder's.
        .modifier(Sweep(picked: $picked, frames: frames))
    }

    private func open(_ session: AgentSession) {
        show(session.id)
    }

    private func show(_ session: AgentSession.ID?) {
        withAnimation(.smooth(duration: 0.35)) { chat = session }
    }
}

struct CornerButton: View {
    let title: String
    let icon: Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconLabel(title, icon)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glass(in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The task box. Above its corner sits the way back to the agents already
/// at work.
struct Composer: View {
    let store: SessionStore
    let picked: Set<URL>
    let open: (AgentSession) -> Void
    @State private var draft = ""
    @FocusState private var composing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Task", text: $draft, prompt: Text(""), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(2...6)
                .focused($composing)
                .onSubmit(send)
                // The system dims its own prompt too far to read on glass.
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Ask for anything on this Mac")
                            .foregroundStyle(Theme.secondary)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                IconLabel(
                    picked.isEmpty
                        ? "Select files to ask about them"
                        : "\(picked.count) selected \(picked.count == 1 ? "item" : "items")",
                    picked.isEmpty ? .cursor : .checkCircle
                )
                .font(.callout)
                .foregroundStyle(Theme.secondary)
                Spacer()
                if store.preferences.agents.count > 1 {
                    agentMenu
                }
                Button(action: send) {
                    IconView(.arrowUp, size: 15)
                        .foregroundStyle(canSend ? Color.white : Theme.secondary)
                        .frame(width: 28, height: 28)
                        .glass(tinted: canSend ? Theme.accent : nil, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Start an agent on this task")
            }
        }
        .padding(14)
        .glass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            AgentsButton(store: store, open: open)
                .offset(y: -40)
        }
    }

    /// Which agent takes the task.
    private var agentMenu: some View {
        Menu {
            ForEach(Agent.allCases.filter(store.preferences.agents.contains)) { agent in
                Button {
                    store.preferences.agent = agent
                } label: {
                    if store.preferences.agent == agent {
                        Label(agent.name, systemImage: "checkmark")
                    } else {
                        Text(agent.name)
                    }
                }
            }
        } label: {
            Text(store.preferences.agent.name)
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(Theme.secondary)
        .help("The agent that takes the task")
    }

    private var task: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool { !task.isEmpty }

    private func send() {
        guard canSend else { return }
        open(store.start(task, about: picked.sorted { $0.path < $1.path }))
        draft = ""
    }
}

/// How many agents there are, and whether one is waiting on the user. A
/// click lists them, with any question they have asked.
private struct AgentsButton: View {
    let store: SessionStore
    let open: (AgentSession) -> Void
    @State private var showsList = false

    var body: some View {
        if !store.sessions.isEmpty {
            Button {
                showsList.toggle()
            } label: {
                HStack(spacing: 6) {
                    IconView(.activity, size: 14)
                    Text("\(store.sessions.count)")
                        .monospacedDigit()
                    if !store.waiting.isEmpty {
                        Circle()
                            .fill(.orange)
                            .frame(width: 7, height: 7)
                    }
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glass(in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(store.waiting.isEmpty ? "Your agents" : "An agent is waiting on you")
            .popover(isPresented: $showsList, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.waiting, id: \.approval.id) { item in
                        ApprovalRow(session: item.session, approval: item.approval)
                    }
                    if !store.waiting.isEmpty {
                        Divider()
                    }
                    ForEach(store.sessions) { session in
                        AgentRow(session: session) {
                            showsList = false
                            open(session)
                        }
                    }
                }
                .padding(14)
                .frame(width: 340)
            }
        }
    }
}

/// A tool call waiting on the user, with the answer right there.
struct ApprovalRow: View {
    let session: AgentSession
    let approval: AgentSession.Approval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(approval.summary)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(3)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text(session.agent.name)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Button("Don\u{2019}t allow") { session.resolve(approval, allow: false) }
                Button("Allow") { session.resolve(approval, allow: true) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
    }
}

struct Widget<Content: View>: View {
    let title: String
    let icon: Icon
    let count: Int?
    /// A set height, for grids whose widgets should all match.
    var height: CGFloat? = nil
    /// A link across from the title, and what it does.
    var link: String? = nil
    var follow: () -> Void = {}
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                IconView(icon)
                    .foregroundStyle(Theme.secondary)
                Text(title)
                    .fontWeight(.medium)
                if let count, count > 0 {
                    Text("\(count)")
                        .foregroundStyle(Theme.secondary)
                }
                if let link {
                    Spacer()
                    Button(link, action: follow)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            .font(.callout)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: height ?? 150, maxHeight: height, alignment: .topLeading)
        .clipped()
        .card()
    }
}

struct Hint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.secondary)
    }
}

struct AgentRow: View {
    let session: AgentSession
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StateDot(state: session.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .lineLimit(1)
                    Text(session.latest.isEmpty ? session.agent.name : session.latest)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StateDot: View {
    let state: AgentSession.State

    var body: some View {
        Circle()
            .fill(colour)
            .frame(width: 7, height: 7)
    }

    private var colour: Color {
        switch state {
        case .idle: .green
        case .working: Theme.accent
        case .waiting: .orange
        case .ended: .gray
        }
    }
}

/// A conversation with an agent, laid over the desktop. The ground is let
/// through just enough to read against, so the picture stays in sight.
struct ChatView: View {
    let session: AgentSession
    let insets: EdgeInsets
    let close: () -> Void
    @State private var draft = ""
    @FocusState private var composing: Bool

    /// How wide the conversation runs.
    private static let column: CGFloat = 820

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: close) {
                    IconLabel("Desktop", .arrowLeft)
                        .font(.callout.weight(.medium))
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                StateDot(state: session.state)
                Text(session.title)
                    .font(.callout)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Spacer()
                Text(status)
                    .font(.callout)
                    .foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: Self.column)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(session.entries) { entry in
                            EntryView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .frame(maxWidth: Self.column, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                }
                .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
                .onChange(of: session.entries.count) {
                    if let last = session.entries.last {
                        withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if !session.approvals.isEmpty {
                VStack(spacing: 12) {
                    ForEach(session.approvals) { approval in
                        ApprovalRow(session: session, approval: approval)
                    }
                }
                .padding(14)
                .card()
                .frame(maxWidth: Self.column)
                .padding(.horizontal, 20)
            }

            TextField("Reply", text: $draft, prompt: Text(""), axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($composing)
                .disabled(session.state == .ended)
                .onSubmit(send)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text(session.state == .ended ? "This conversation has ended" : "Reply")
                            .foregroundStyle(Theme.secondary)
                            .allowsHitTesting(false)
                    }
                }
                .padding(14)
                .glass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: Self.column)
                .padding(20)
        }
        .padding(insets)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground.opacity(0.66))
        .onAppear { composing = true }
    }

    private var status: String {
        switch session.state {
        case .idle: session.model.isEmpty ? session.agent.name : session.model
        case .working: "Working"
        case .waiting: "Waiting on you"
        case .ended: "Ended"
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        session.send(text)
    }
}

struct EntryView: View {
    let entry: AgentSession.Entry

    var body: some View {
        switch entry.kind {
        case .user:
            Text(entry.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .assistant:
            Text(entry.text)
                .textSelection(.enabled)
        case .tool:
            Text(entry.text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
        case .error:
            Text(entry.text)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }
}
