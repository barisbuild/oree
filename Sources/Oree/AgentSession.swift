import Foundation
import Observation

/// The command-line agents Oree can put to work. Each is the user's own
/// install, signed in with the user's own account; Oree holds no keys.
enum Agent: String, CaseIterable, Identifiable, Codable {
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
/// Codex runs as an app server for the whole conversation and speaks
/// JSON-RPC over the same pipes. Its sandbox lets it read but not write;
/// anything that would change a file comes to the user as a request first.
@Observable
final class AgentSession: Identifiable {
    enum State { case idle, working, waiting, ended }

    struct Entry: Identifiable, Codable {
        enum Kind: String, Codable { case user, assistant, tool, error }
        let id: UUID
        let kind: Kind
        let text: String
        /// When it arrived, so a new answer can be shown arriving.
        let at: Date

        init(kind: Kind, text: String) {
            id = UUID()
            self.kind = kind
            self.text = text
            at = Date()
        }
    }

    /// What is kept of a conversation between launches: enough to show it
    /// again and for its agent to take it up where it left off.
    struct Record: Codable {
        let id: UUID
        let agent: Agent
        let folder: URL
        let entries: [Entry]
        /// Claude Code's session, or Codex's thread.
        let resume: String?
        let model: String
    }

    /// A tool call the agent may not make until the user says so.
    struct Approval: Identifiable {
        let id: String
        let summary: String
        fileprivate let input: [String: Any]
        /// Codex only: the request to answer, and what it asked for.
        fileprivate var request: Any? = nil
        fileprivate var method = ""
    }

    let id: UUID
    let agent: Agent
    let folder: URL
    /// The agent's own name for the conversation, so it can be resumed.
    private(set) var resume: String?
    /// The agent process is running. A conversation brought back from a
    /// past launch starts it only when there is something to send.
    @ObservationIgnored private var started = false
    /// Whether the user has chosen to let agents act without asking. Read
    /// at each request, so a change applies to the next one.
    @ObservationIgnored private let bypass: () -> Bool
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
    /// Messages typed before Codex had a conversation to put them in.
    @ObservationIgnored private var early: [String] = []
    /// Requests sent to Codex and not yet answered, by id.
    @ObservationIgnored private var calls: [Int: String] = [:]
    @ObservationIgnored private var nextCall = 0

    init(agent: Agent, folder: URL, bypass: @escaping () -> Bool = { false }) {
        id = UUID()
        self.agent = agent
        self.folder = folder
        self.bypass = bypass
        start()
    }

    /// A conversation from a past launch, shown as it was.
    init(record: Record, bypass: @escaping () -> Bool = { false }) {
        id = record.id
        agent = record.agent
        folder = record.folder
        self.bypass = bypass
        entries = record.entries
        resume = record.resume
        model = record.model
        // Without the agent's name for it, it cannot be taken up again.
        state = record.resume == nil ? .ended : .idle
    }

    var record: Record {
        Record(id: id, agent: agent, folder: folder, entries: entries, resume: resume, model: model)
    }

    /// Start the agent, taking up the conversation if it has a name for it.
    private func start() {
        started = true
        if Demo.on { return }
        switch agent {
        case .claude:
            let resuming = resume.map { " --resume '\($0)'" } ?? ""
            run("exec claude --print --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio\(resuming) --append-system-prompt '\(Self.desktopBrief)'")
        case .codex:
            run("exec codex app-server")
            call("initialize", ["clientInfo": ["name": "oree", "title": "Oree", "version": "1"]])
        }
    }

    /// Send a message. `shownAs` is what the transcript shows when the
    /// message carries context the user did not type.
    func send(_ text: String, shownAs shown: String? = nil) {
        guard state != .ended else { return }
        if !started { start() }
        entries.append(Entry(kind: .user, text: shown ?? text))
        state = .working
        if Demo.on {
            playDemo()
            return
        }
        switch agent {
        case .claude:
            write(["type": "user", "message": ["role": "user", "content": text]])
        case .codex:
            if thread == nil { early.append(text) } else { askCodex(text) }
        }
    }

    /// For recordings: a short, believable turn with nothing actually run.
    private func playDemo() {
        let steps: [(Double, Entry.Kind, String)] = [
            (0.4, .tool, "Shell: ls -lt ~/Downloads"),
            (0.7, .tool, "Shell: mkdir -p ~/Downloads/{September,October,November}"),
            (1.0, .tool, "Shell: mv ~/Downloads/*.pdf ~/Downloads/November/"),
            (1.35, .assistant, "Done. Your Downloads are sorted into **September**, **October** and **November**, 46 files in all. Nothing was deleted."),
        ]
        for (delay, kind, text) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.entries.append(Entry(kind: kind, text: text))
                if kind == .assistant { self?.state = .idle }
            }
        }
    }

    /// Start one Codex turn. Everyday chores on a desktop need little
    /// thought, so it is asked to reason lightly and answer sooner.
    private func askCodex(_ prompt: String) {
        guard let thread else { return }
        lastPrompt = prompt
        var params: [String: Any] = [
            "threadId": thread,
            "input": [["type": "text", "text": prompt]],
            "effort": "low",
        ]
        if let model = Self.codexModel() {
            params["model"] = model
            self.model = model
        }
        call("turn/start", params)
    }

    /// A JSON-RPC request to Codex; the answer comes back by id.
    private func call(_ method: String, _ params: [String: Any]) {
        nextCall += 1
        calls[nextCall] = method
        write(["id": nextCall, "method": method, "params": params])
    }

    /// Answer a tool call the agent is waiting on.
    func resolve(_ approval: Approval, allow: Bool) {
        guard let index = approvals.firstIndex(where: { $0.id == approval.id }) else { return }
        approvals.remove(at: index)
        if let request = approval.request {
            // Codex: a further permission is granted for this turn only;
            // a command or a file change is accepted or declined.
            let result: [String: Any] = approval.method == "item/permissions/requestApproval"
                ? ["permissions": allow ? approval.input : [:], "scope": "turn"]
                : ["decision": allow ? "accept" : "decline"]
            write(["id": request, "result": result])
        } else {
            let decision: [String: Any] = allow
                ? ["behavior": "allow", "updatedInput": approval.input]
                : ["behavior": "deny", "message": "The user denied this action."]
            write([
                "type": "control_response",
                "response": ["subtype": "success", "request_id": approval.id, "response": decision],
            ])
        }
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

    /// Models the service has refused this account, and the one settled on
    /// in their place. Shared by every conversation, and remembered across
    /// launches so a refused model costs one failed turn, not one a launch.
    private static var refused: Set<String> = []
    private static var replacement: String? {
        get { UserDefaults.standard.string(forKey: "codexModel") }
        set { UserDefaults.standard.set(newValue, forKey: "codexModel") }
    }

    /// The models Codex lists for the signed-in account.
    private static var listed: [String] {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: file),
              let cache = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return (cache["models"] as? [[String: Any]])?.compactMap { $0["slug"] as? String } ?? []
    }

    /// Desktop chores want a quick answer more than deep thought, so Oree
    /// asks for Codex's fast model while the account lists it.
    private static let preferred = "gpt-6-luna"

    /// The model to ask Codex for: the fast one if the account has it, else
    /// one settled on after a refusal. Nil leaves Codex's own choice alone.
    static func codexModel() -> String? {
        if !refused.contains(preferred), listed.contains(preferred) { return preferred }
        return replacement
    }

    /// The service refused a model: note which, and choose the next listed.
    /// False when there is nothing left to try.
    private static func replace(refusedIn message: String) -> Bool {
        // "The 'some-model' model is not supported …": the name is quoted.
        let parts = message.split(separator: "'")
        if parts.count >= 3 { refused.insert(String(parts[1])) }
        if let current = codexModel() { refused.insert(current) }
        replacement = listed.first { !refused.contains($0) }
        return replacement != nil
    }

    /// Passed inside single quotes on a shell command line: no apostrophes.
    private static let desktopBrief = """
        You are helping with everyday tasks on this Mac, not with a code project. \
        The user asks you to find, organise, rename, move and summarise files and folders, \
        and to answer questions. Work from the home folder. \
        Move things to the Trash rather than deleting them. \
        Keep answers short and say plainly what you changed. \
        Write the way a person talks in a chat: plain sentences, a short list only when it helps, \
        no headings, no tables and no links to file paths.
        """

    private func ended() {
        approvals.removeAll()
        let unfinished = state == .working || state == .waiting
        if unfinished {
            // A turn cut short has no closing event; what the process wrote
            // to stderr is the only explanation there is.
            let detail = String(decoding: errorOutput.suffix(600), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(Entry(kind: .error, text: detail.isEmpty ? "\(agent.name) stopped." : detail))
        }
        // Either agent leaving means the conversation is over.
        state = .ended
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
            if event["subtype"] as? String == "init" {
                if let name = event["model"] as? String { model = name }
                if let session = event["session_id"] as? String { resume = session }
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
            ask(Approval(
                id: id,
                summary: Self.describe(tool: request["tool_name"] as? String, input: input),
                input: input
            ))
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

    // MARK: Codex's messages

    private func handleCodex(_ message: [String: Any]) {
        let method = message["method"] as? String
        let params = message["params"] as? [String: Any] ?? [:]
        if let id = message["id"] {
            if let method {
                codexAsks(method, id: id, params: params)
            } else if let number = (id as? NSNumber)?.intValue {
                codexAnswered(calls.removeValue(forKey: number), message)
            }
            return
        }
        switch method {
        case "turn/started":
            break
        case "item/started":
            // Commands and changes are noted as they begin, before any
            // request to allow them, the way Claude Code's are.
            guard let item = params["item"] as? [String: Any] else { break }
            switch item["type"] as? String {
            case "commandExecution":
                if let command = item["command"] as? String {
                    entries.append(Entry(kind: .tool, text: "Shell: \(Self.unwrap(command))"))
                }
            case "fileChange":
                let paths = (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
                entries.append(Entry(kind: .tool, text: "Edit: \(paths.joined(separator: ", "))"))
            default:
                break
            }
        case "item/completed":
            guard let item = params["item"] as? [String: Any],
                  item["type"] as? String == "agentMessage",
                  let text = item["text"] as? String, !text.isEmpty
            else { break }
            entries.append(Entry(kind: .assistant, text: text))
        case "error":
            guard params["willRetry"] as? Bool != true else { break }
            let message = (params["error"] as? [String: Any])?["message"] as? String ?? "Codex could not finish the turn."
            let plain = Self.plain(message)
            // The account may not use this model: try the next one quietly.
            if plain.contains("model"), plain.contains("not supported") || message.contains("model_not_found"),
               !asksAgain, Self.replace(refusedIn: plain) {
                asksAgain = true
                break
            }
            if entries.last?.text != plain {
                entries.append(Entry(kind: .error, text: plain))
            }
        case "turn/completed":
            approvals.removeAll()
            // A turn refused over its model is put again with another model.
            if asksAgain {
                asksAgain = false
                askCodex(lastPrompt)
                break
            }
            state = .idle
        default:
            break
        }
    }

    /// Codex's answer to a request of ours.
    private func codexAnswered(_ method: String?, _ message: [String: Any]) {
        if let error = message["error"] as? [String: Any] {
            entries.append(Entry(kind: .error, text: error["message"] as? String ?? "Codex refused a request."))
            // Without a conversation there is nothing more to do.
            if method == "initialize" || method == "thread/start" || method == "thread/resume" { stop() } else { state = .idle }
            return
        }
        let result = message["result"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            write(["method": "initialized"])
            // Reading is free; writing anything is asked for first.
            var params: [String: Any] = [
                "cwd": folder.path,
                "sandbox": "read-only",
                "approvalPolicy": "on-request",
                "developerInstructions": Self.desktopBrief,
            ]
            if let model = Self.codexModel() { params["model"] = model }
            // A conversation from before is taken up by its thread.
            if let resume {
                params["threadId"] = resume
                call("thread/resume", params)
            } else {
                call("thread/start", params)
            }
        case "thread/start", "thread/resume":
            thread = (result["thread"] as? [String: Any])?["id"] as? String
            resume = thread
            model = result["model"] as? String ?? ""
            let waiting = early
            early = []
            waiting.forEach(askCodex)
        default:
            break
        }
    }

    /// A request from Codex: to run a command, change files or widen its
    /// sandbox. Each waits for the user; anything else is declined.
    private func codexAsks(_ method: String, id: Any, params: [String: Any]) {
        let reason = params["reason"] as? String
        let summary: String
        var input: [String: Any] = [:]
        switch method {
        case "item/commandExecution/requestApproval":
            summary = "Shell: \(Self.unwrap(params["command"] as? String ?? reason ?? "a command"))"
        case "item/fileChange/requestApproval":
            summary = "Edit: \(params["grantRoot"] as? String ?? reason ?? "files")"
        case "item/permissions/requestApproval":
            summary = "Access: \(reason ?? "more of this Mac")"
            input = params["permissions"] as? [String: Any] ?? [:]
        default:
            write(["id": id, "error": ["code": -32601, "message": "Oree does not handle \(method)."]])
            return
        }
        ask(Approval(id: "\(id)", summary: summary, input: input, request: id, method: method))
    }

    /// Put a request to the user, or allow it at once when they have chosen
    /// to bypass the asking; it is noted in the conversation either way.
    private func ask(_ approval: Approval) {
        approvals.append(approval)
        state = .waiting
        if bypass() { resolve(approval, allow: true) }
    }

    /// "/bin/zsh -lc 'mkdir Notes'" is shown as "mkdir Notes".
    private static func unwrap(_ command: String) -> String {
        for shell in ["/bin/zsh -lc ", "/bin/bash -lc ", "bash -lc ", "zsh -lc "] where command.hasPrefix(shell) {
            var inner = command.dropFirst(shell.count)
            if inner.hasPrefix("'"), inner.hasSuffix("'"), inner.count >= 2 { inner = inner.dropFirst().dropLast() }
            return String(inner)
        }
        return command
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
