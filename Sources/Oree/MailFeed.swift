import AppKit
import Observation
import SQLite3
import SwiftUI

/// The newest messages in the inbox. Read from Mail's own index on disk, so
/// Mail need not be open; that takes Full Disk Access, given once. Without
/// it, Mail is asked directly whenever it happens to be running.
@Observable
final class MailFeed {
    struct Message: Identifiable {
        let id: Int
        let subject: String
        let sender: String
        let unread: Bool
    }

    enum State { case loading, ready, needsAccess }

    private(set) var messages: [Message] = []
    private(set) var state = State.loading

    private static let bundle = "com.apple.mail"

    func refresh() {
        if Demo.on {
            messages = [
                Message(id: 1, subject: "Your tickets for Friday", sender: "Box office", unread: true),
                Message(id: 2, subject: "Invoice 0142 is paid", sender: "Billing", unread: true),
                Message(id: 3, subject: "Notes from Tuesday", sender: "Studio", unread: false),
                Message(id: 4, subject: "The week in type", sender: "Newsletter", unread: false),
                Message(id: 5, subject: "Proofs are ready", sender: "Print shop", unread: false),
            ]
            state = .ready
            return
        }
        let mailIsOpen = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundle).isEmpty
        Task.detached(priority: .utility) {
            let found = Self.readIndex() ?? (mailIsOpen ? Self.askMail() : nil)
            await MainActor.run {
                if let found {
                    self.messages = found
                    self.state = .ready
                } else if self.messages.isEmpty {
                    self.state = .needsAccess
                }
            }
        }
    }

    func openMail() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundle) else { return }
        NSWorkspace.shared.open(app)
    }

    func openAccessSettings() {
        guard let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(pane)
    }

    // MARK: Mail's index

    /// Nil when the index cannot be opened or read, which is what happens
    /// without Full Disk Access.
    static func readIndex() -> [Message]? {
        let mail = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
        // "V10", "V11": the newest layout wins.
        guard let version = (try? FileManager.default.contentsOfDirectory(atPath: mail.path))?
            .filter({ $0.hasPrefix("V") })
            .max(by: { (Int($0.dropFirst()) ?? 0) < (Int($1.dropFirst()) ?? 0) })
        else { return nil }
        let index = mail.appendingPathComponent(version).appendingPathComponent("MailData/Envelope Index")

        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(index.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(database, 500)

        // A message is in an inbox when it is filed there, or, as Gmail
        // does it, filed elsewhere and labelled with the inbox.
        let inboxes = "SELECT ROWID FROM mailboxes WHERE url LIKE '%/INBOX'"
        func query(labelled: Bool) -> String {
            """
            SELECT subjects.subject, addresses.comment, addresses.address, messages.read
            FROM messages
            JOIN subjects ON messages.subject = subjects.ROWID
            JOIN addresses ON messages.sender = addresses.ROWID
            WHERE messages.deleted = 0 AND (messages.mailbox IN (\(inboxes))
                \(labelled ? "OR messages.ROWID IN (SELECT message_id FROM labels WHERE mailbox_id IN (\(inboxes)))" : ""))
            ORDER BY messages.date_received DESC
            LIMIT 5
            """
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        // An index without a labels table still answers the plain question.
        if sqlite3_prepare_v2(database, query(labelled: true), -1, &statement, nil) != SQLITE_OK {
            sqlite3_finalize(statement)
            statement = nil
            guard sqlite3_prepare_v2(database, query(labelled: false), -1, &statement, nil) == SQLITE_OK else { return nil }
        }

        var messages: [Message] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            func text(_ column: Int32) -> String {
                sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            }
            let name = text(1)
            messages.append(Message(
                id: messages.count,
                subject: text(0),
                sender: name.isEmpty ? text(2) : name,
                unread: sqlite3_column_int(statement, 3) == 0
            ))
        }
        return messages
    }

    /// Every mailbox with its message count; account names are left out.
    static func mailboxReport() -> String {
        let mail = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
        guard let version = (try? FileManager.default.contentsOfDirectory(atPath: mail.path))?
            .filter({ $0.hasPrefix("V") })
            .max(by: { (Int($0.dropFirst()) ?? 0) < (Int($1.dropFirst()) ?? 0) })
        else { return "no Mail folder" }
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        let index = mail.appendingPathComponent(version).appendingPathComponent("MailData/Envelope Index")
        guard sqlite3_open_v2(index.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return "cannot open index" }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT mailboxes.url, COUNT(messages.ROWID), SUM(messages.deleted) FROM mailboxes LEFT JOIN messages ON messages.mailbox = mailboxes.ROWID GROUP BY mailboxes.ROWID"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return "query failed: " + String(cString: sqlite3_errmsg(database))
        }
        var lines: [String] = [version]
        while sqlite3_step(statement) == SQLITE_ROW {
            let url = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            // "imap://account/INBOX": keep the scheme and the path only.
            let parts = url.components(separatedBy: "://")
            let path = parts.count > 1 ? parts[1].split(separator: "/", maxSplits: 1).dropFirst().joined() : url
            lines.append("\(parts.first ?? "") | /\(path) | \(sqlite3_column_int(statement, 1)) messages, \(sqlite3_column_int(statement, 2)) deleted")
        }
        let found = readIndex()
        lines.append("inbox query: \(found.map { "\($0.count) messages, senders: " + $0.map(\.sender).joined(separator: ", ") } ?? "failed")")
        return lines.joined(separator: "\n")
    }

    // MARK: Mail itself

    private static let script = """
        tell application "Mail"
            set total to count of messages of inbox
            if total > 5 then set total to 5
            set out to ""
            repeat with index from 1 to total
                set letter to message index of inbox
                set out to out & (subject of letter) & tab & (sender of letter) & tab & (read status of letter) & linefeed
            end repeat
            return out
        end tell
        """

    private static func askMail() -> [Message]? {
        guard let output = Shell.appleScript(script) else { return nil }
        return output.split(separator: "\n").enumerated().compactMap { index, row in
            let fields = row.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3 else { return nil }
            // "Ada Lovelace <ada@example.com>": the name is enough.
            let sender = fields[1].split(separator: "<").first.map(String.init) ?? String(fields[1])
            return Message(
                id: index,
                subject: String(fields[0]),
                sender: sender.trimmingCharacters(in: .whitespaces),
                unread: fields[2] == "false"
            )
        }
    }
}

struct MailWidget: View {
    let feed: MailFeed

    var body: some View {
        Widget(title: "Mail", icon: .mail, count: feed.messages.filter(\.unread).count, height: widgetHeight) {
            switch feed.state {
            case .loading:
                Hint("Reading your inbox…")
            case .needsAccess:
                VStack(alignment: .leading, spacing: 10) {
                    Hint("Give Oree Full Disk Access once and your inbox shows here, with Mail closed too.")
                    HStack {
                        Button("Open Privacy Settings", action: feed.openAccessSettings)
                        Button("Open Mail instead", action: feed.openMail)
                    }
                    .controlSize(.small)
                }
            case .ready where feed.messages.isEmpty:
                Hint("The inbox is empty.")
            case .ready:
                VStack(spacing: 2) {
                    ForEach(feed.messages) { message in
                        Button(action: feed.openMail) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                // The subject lines up with the title; the
                                // unread dot sits out in the margin.
                                Text(message.subject)
                                    .fontWeight(message.unread ? .medium : .regular)
                                    .lineLimit(1)
                                    .overlay(alignment: .leading) {
                                        if message.unread {
                                            Circle()
                                                .fill(Theme.accent)
                                                .frame(width: 6, height: 6)
                                                .offset(x: -10)
                                        }
                                    }
                                Spacer(minLength: 8)
                                Text(message.sender)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
