import Foundation

/// Running the system's own tools.
enum Shell {
    /// Run a program and read what it prints. Nil when it cannot start or
    /// reports failure.
    static func output(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    /// Open a file or an app the way a double click would.
    static func open(_ url: URL) {
        _ = output("/usr/bin/open", [url.path])
    }

    static func appleScript(_ source: String) -> String? {
        output("/usr/bin/osascript", ["-e", source])
    }

}

extension URLSession {
    /// For the few requests Oree makes. It keeps nothing on disk: the shared
    /// session leaves a folder named after the app in ~/Library/HTTPStorages,
    /// which Spotlight then offers as a second copy of the app.
    static let oree = URLSession(configuration: .ephemeral)
}
