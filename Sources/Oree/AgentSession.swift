import Foundation
import Observation

/// The command-line agents Oree can put to work. Each is the user's own
/// install, signed in with the user's own account; Oree holds no keys.
enum Agent: String, CaseIterable, Identifiable {
    case claude, codex

    var id: Self { self }
    var name: String { self == .claude ? "Claude Code" : "Codex" }
    var command: String { rawValue }
    /// What to run in a terminal to sign in.
    var signIn: String { self == .claude ? "claude" : "codex login" }
    /// What to run in a terminal to install it.
    var install: String {
        self == .claude ? "npm install -g @anthropic-ai/claude-code" : "npm install -g @openai/codex"
    }
}

/// One agent working in one folder, over one conversation.
///
/// Claude Code stays running between turns: each user message is one JSON
/// line on its stdin, each event one JSON line on its stdout, and it asks
/// over the same stream before a tool call that needs permission.
///
/// Codex runs once per turn and is resumed by thread for the next. It has
/// no way to ask first, so its sandbox is what holds it: it may read around
/// the Mac but change nothing.
@Observable
final class AgentSession: Identifiable {
    enum State { case idle, working, waiting, ended }

    struct Entry: Identifiable {
        enum Kind { case user, assistant, tool, error }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    /// A tool call the agent may not make until the user says so.
    struct Approval: Identifiable {
        let id: String
        let summary: String
        fileprivate let input: [String: Any]
    }

    let id = UUID()
    let agent: Agent
    let folder: URL
    private(set) var entries: [Entry] = []
    private(set) var approvals: [Approval] = []
    private(set) var state: State = .idle
    private(set) var model = ""

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input = Pipe()
    @ObservationIgnored private var pending = Data()
    @ObservationIgnored private var errorOutput = Data()
    /// What Codex was last asked, kept in case the turn has to be put again.
    @ObservationIgnored private var lastPrompt = ""
    /// The turn failed over the model and should be put again with another.
    @ObservationIgnored private var asksAgain = false
    /// Codex's name for this conversation, once it has given one.
    @ObservationIgnored private var thread: String?

    init(agent: Agent, folder: URL) {
        self.agent = agent
        self.folder = folder
        if agent == .claude {
            run("exec claude --print --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio --append-system-prompt '\(Self.desktopBrief)'")
        }
    }

    /// Send a message. `shownAs` is what the transcript shows when the
    /// message carries context the user did not type.
    func send(_ text: String, shownAs shown: String? = nil) {
        guard state != .ended else { return }
        entries.append(Entry(kind: .user, text: shown ?? text))
        state = .working
        switch agent {
        case .claude:
            write(["type": "user", "message": ["role": "user", "content": text]])
        case .codex:
            askCodex(thread == nil ? Self.desktopBrief + "\n\n" + text : text)
        }
    }

    /// Run one Codex turn. The prompt goes in on stdin (`-`), so nothing in
    /// it meets the shell.
    private func askCodex(_ prompt: String) {
        lastPrompt = prompt
        let model = Self.codexModel().map { " -m \($0)" } ?? ""
        let options = "--json --skip-git-repo-check -c 'sandbox_mode=\"read-only\"'\(model) -"
        run(thread.map { "exec codex exec resume \($0) \(options)" } ?? "exec codex exec \(options)")
        write(text: prompt)
        try? input.fileHandleForWriting.close()
    }

    /// Answer a tool call the agent is waiting on.
    func resolve(_ approval: Approval, allow: Bool) {
        guard let index = approvals.firstIndex(where: { $0.id == approval.id }) else { return }
        approvals.remove(at: index)
        let decision: [String: Any] = allow
            ? ["behavior": "allow", "updatedInput": approval.input]
            : ["behavior": "deny", "message": "The user denied this action."]
        write([
            "type": "control_response",
            "response": ["subtype": "success", "request_id": approval.id, "response": decision],
        ])
        entries.append(Entry(kind: .tool, text: "\(allow ? "Allowed" : "Denied") · \(approval.summary)"))
        if state == .waiting, approvals.isEmpty { state = .working }
    }

    func stop() {
        if process?.isRunning == true { process?.terminate() }
    }

    // MARK: The process

    private func run(_ command: String) {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        input = Pipe()
        pending = Data()
        errorOutput = Data()
        // A login, interactive shell, so the CLI is found where the user's
        // terminal finds it (nvm, Homebrew) even though the app was started
        // by the system with a bare PATH.
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", command]
        process.currentDirectoryURL = folder
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // Nothing to read means the other end has closed. Stop
            // listening, or this is called again and again for ever.
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.consume(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // Nothing to read means the other end has closed. Stop
            // listening, or this is called again and again for ever.
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.errorOutput.append(data) }
        }
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                // Only the process now in use speaks for the session.
                if self?.process === finished { self?.ended() }
            }
        }

        self.process = process
        do {
            try process.run()
        } catch {
            entries.append(Entry(kind: .error, text: "Could not start \(agent.name): \(error.localizedDescription)"))
            state = .ended
        }
    }

    private func write(_ message: [String: Any]) {
        guard var line = try? JSONSerialization.data(withJSONObject: message) else { return }
        line.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: line)
    }

    private func write(text: String) {
        try? input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
    }

    /// Models the service has refused this account, and the one settled on
    /// in their place. Shared by every conversation.
    private static var refused: Set<String> = []
    private static var replacement: String?

    /// The models Codex lists for the signed-in account.
    private static var listed: [String] {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: file),
              let cache = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return (cache["models"] as? [[String: Any]])?.compactMap { $0["slug"] as? String } ?? []
    }

    /// The model to ask Codex for. Nil leaves Codex's own choice alone,
    /// which is right until the service says the account may not use it.
    static func codexModel() -> String? {
        replacement
    }

    /// The service refused a model: note which, and choose the next listed.
    /// False when there is nothing left to try.
    private static func replace(refusedIn message: String) -> Bool {
        // "The 'some-model' model is not supported …": the name is quoted.
        let parts = message.split(separator: "'")
        if parts.count >= 3 { refused.insert(String(parts[1])) }
        if let replacement { refused.insert(replacement) }
        replacement = listed.first { !refused.contains($0) }
        return replacement != nil
    }

    /// Passed inside single quotes on a shell command line: no apostrophes.
    private static let desktopBrief = """
        You are helping with everyday tasks on this Mac, not with a code project. \
        The user asks you to find, organise, rename, move and summarise files and folders, \
        and to answer questions. Work from the home folder. \
        Move things to the Trash rather than deleting them. \
        Keep answers short and say plainly what you changed.
        """

    private func ended() {
        // A turn refused over its model is put again with another model.
        if asksAgain {
            asksAgain = false
            state = .working
            askCodex(lastPrompt)
            return
        }
        approvals.removeAll()
        let unfinished = state == .working || state == .waiting
        if unfinished {
            // A turn cut short has no closing event; what the process wrote
            // to stderr is the only explanation there is.
            let detail = String(decoding: errorOutput.suffix(600), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(Entry(kind: .error, text: detail.isEmpty ? "\(agent.name) stopped." : detail))
        }
        // Codex leaves after every turn and can be resumed; Claude Code
        // leaving means the conversation is over.
        state = agent == .codex && thread != nil ? .idle : .ended
    }

    private func consume(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            // Shell startup files may print before the CLI takes over; those
            // lines are not JSON and are skipped.
            if let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                switch agent {
                case .claude: handleClaude(event)
                case .codex: handleCodex(event)
                }
            }
        }
    }

    // MARK: Claude Code's events

    private func handleClaude(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "system":
            if event["subtype"] as? String == "init", let name = event["model"] as? String {
                model = name
            }
        case "assistant":
            let message = event["message"] as? [String: Any]
            for block in message?["content"] as? [[String: Any]] ?? [] {
                switch block["type"] as? String {
                case "text":
                    if let text = block["text"] as? String, !text.isEmpty {
                        entries.append(Entry(kind: .assistant, text: text))
                    }
                case "tool_use":
                    entries.append(Entry(kind: .tool, text: Self.describe(
                        tool: block["name"] as? String,
                        input: block["input"] as? [String: Any]
                    )))
                default:
                    break
                }
            }
        case "control_request":
            guard let id = event["request_id"] as? String,
                  let request = event["request"] as? [String: Any],
                  request["subtype"] as? String == "can_use_tool"
            else { break }
            let input = request["input"] as? [String: Any] ?? [:]
            approvals.append(Approval(
                id: id,
                summary: Self.describe(tool: request["tool_name"] as? String, input: input),
                input: input
            ))
            state = .waiting
        case "result":
            if event["is_error"] as? Bool == true,
               let text = event["result"] as? String,
               entries.last?.text != text {
                entries.append(Entry(kind: .error, text: text))
            }
            approvals.removeAll()
            state = .idle
        default:
            break
        }
    }

    /// "Bash: pnpm test", "Read: src/app/page.tsx": the tool and the one
    /// argument that says what it is doing.
    private static func describe(tool: String?, input: [String: Any]?) -> String {
        let name = tool ?? "Tool"
        let input = input ?? [:]
        for key in ["command", "file_path", "pattern", "url", "description", "prompt"] {
            if let value = input[key] as? String {
                return "\(name): \(value)"
            }
        }
        return name
    }

    // MARK: Codex's events

    private func handleCodex(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "thread.started":
            thread = event["thread_id"] as? String
        case "item.completed":
            guard let item = event["item"] as? [String: Any] else { break }
            switch item["type"] as? String {
            case "agent_message":
                if let text = item["text"] as? String, !text.isEmpty {
                    entries.append(Entry(kind: .assistant, text: text))
                }
            case "command_execution":
                if let command = item["command"] as? String {
                    entries.append(Entry(kind: .tool, text: "Shell: \(command)"))
                }
            case "file_change":
                let paths = (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
                entries.append(Entry(kind: .tool, text: "Edit: \(paths.joined(separator: ", "))"))
            case "error":
                // Notes about the setup, not about the task.
                break
            default:
                break
            }
        case "error", "turn.failed":
            let message = event["message"] as? String
                ?? (event["error"] as? [String: Any])?["message"] as? String
                ?? "Codex could not finish the turn."
            let plain = Self.plain(message)
            // The account may not use this model: try the next one quietly.
            if plain.contains("model"), plain.contains("not supported") || message.contains("model_not_found") {
                if asksAgain { break }
                if Self.replace(refusedIn: plain) {
                    asksAgain = true
                    break
                }
            }
            if entries.last?.text != plain {
                entries.append(Entry(kind: .error, text: plain))
            }
            state = .idle
        case "turn.completed":
            state = .idle
        default:
            break
        }
    }

    /// Codex wraps the service's error in JSON; the sentence inside is what
    /// a person can use.
    private static func plain(_ message: String) -> String {
        guard let wrapped = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any],
              let inner = (wrapped["error"] as? [String: Any])?["message"] as? String
        else { return message }
        return inner
    }
}

extension AgentSession {
    /// The task it was started with.
    var title: String {
        entries.first { $0.kind == .user }?.text ?? folder.lastPathComponent
    }

    /// What it last said or did.
    var latest: String {
        entries.last { $0.kind != .user }?.text ?? ""
    }
}

/// Whether each agent is installed and signed in, as its own CLI reports it.
@Observable
final class AgentCheck {
    struct Status {
        var installed = false
        var signedIn = false
    }

    private(set) var statuses: [Agent: Status] = [:]
    private(set) var checking = false

    func status(of agent: Agent) -> Status {
        statuses[agent] ?? Status()
    }

    func refresh() {
        guard !checking else { return }
        checking = true
        Task.detached(priority: .userInitiated) {
            let found = Dictionary(uniqueKeysWithValues: Agent.allCases.map { ($0, Self.check($0)) })
            await MainActor.run {
                self.statuses = found
                self.checking = false
            }
        }
    }

    private static func check(_ agent: Agent) -> Status {
        func shell(_ command: String) -> (output: String, ok: Bool) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lic", command]
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return ("", false) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (String(decoding: data, as: UTF8.self), process.terminationStatus == 0)
        }
        guard shell("command -v \(agent.command)").ok else { return Status() }
        switch agent {
        case .claude:
            let report = shell("claude auth status").output
            return Status(installed: true, signedIn: report.contains("\"loggedIn\": true"))
        case .codex:
            let report = shell("codex login status")
            return Status(installed: true, signedIn: report.ok && report.output.contains("Logged in"))
        }
    }

    /// Open Terminal with a command typed and run, for signing in or
    /// installing: both need a person at the keyboard.
    func runInTerminal(_ command: String) {
        let script = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oree-setup.command")
        try? "#!/bin/zsh -li\n\(command)\n".write(to: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        Shell.open(script)
    }
}
