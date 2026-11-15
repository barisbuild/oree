import AppKit

// `Oree --take-desktop-role` does what the Settings button does, for scripts.
if CommandLine.arguments.contains("--take-desktop-role") {
    let role = DesktopRole()
    role.turnOn()
    if let problem = role.problem { print(problem) }
    exit(role.isOn ? 0 : 1)
}

// `Oree --repair-desktop-role` registers the login agent again, for when
// the system's record of it no longer matches the installed app.
if CommandLine.arguments.contains("--repair-desktop-role") {
    exit(DesktopRole.reregister() ? 0 : 1)
}

// `Oree --check-access` reports which protected places this app can open.
if CommandLine.arguments.contains("--check-access") {
    let home = NSHomeDirectory()
    let report = ["Library/Application Support/com.apple.TCC/TCC.db", "Library/Mail", "Library/Safari/History.db", "Desktop", "Documents"]
        .map { path -> String in
            let full = home + "/" + path
            let opened = FileHandle(forReadingAtPath: full) != nil
                || (try? FileManager.default.contentsOfDirectory(atPath: full)) != nil
            return "\(opened ? "yes" : "no ")  \(path)"
        }
        .joined(separator: "\n")
    try? report.write(toFile: NSTemporaryDirectory() + "oree-access.txt", atomically: true, encoding: .utf8)
    exit(0)
}

// `Oree --mail-boxes` lists the mailboxes in Mail's index and how many
// messages each holds, to see which ones the inbox query should cover.
if CommandLine.arguments.contains("--mail-boxes") {
    try? MailFeed.mailboxReport().write(toFile: NSTemporaryDirectory() + "oree-mail.txt", atomically: true, encoding: .utf8)
    exit(0)
}

// `Oree --codex-model` says which model Oree would ask Codex for.
if CommandLine.arguments.contains("--codex-model") {
    try? (AgentSession.codexModel() ?? "Codex's own choice").write(toFile: NSTemporaryDirectory() + "oree-codex.txt", atomically: true, encoding: .utf8)
    exit(0)
}

DesktopRole.settleWithOtherCopies()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// No Dock icon and no Cmd+Tab entry: the app is the desktop, not a window on it.
app.setActivationPolicy(.accessory)
app.run()
