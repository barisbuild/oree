import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// What the user has chosen, kept across launches.
@Observable
final class Preferences {
    /// The agents the user chose to use: either, or both.
    var agents: Set<Agent> {
        didSet {
            defaults.set(agents.map(\.rawValue), forKey: "agents")
            if !agents.contains(agent), let other = agents.first { agent = other }
        }
    }
    /// The agent new tasks go to.
    var agent: Agent { didSet { defaults.set(agent.rawValue, forKey: "agent") } }
    /// The first-run choices have been made.
    var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    /// Offer the Desktop folder itself among the folders.
    var showsFiles: Bool { didSet { defaults.set(showsFiles, forKey: "showsFiles") } }
    /// Gather a folder's items into one pile per kind.
    var stacks: Bool { didSet { defaults.set(stacks, forKey: "stacks") } }
    /// Folders kept one click away.
    var pinned: [URL] { didSet { defaults.set(pinned.map(\.path), forKey: "pinned") } }
    /// Agents act without asking first. Off unless the user has turned it on
    /// and accepted that Oree is not responsible for what follows.
    var bypassPermissions: Bool { didSet { defaults.set(bypassPermissions, forKey: "bypassPermissions") } }
    /// The chosen picture; nil follows the system's own wallpaper.
    var wallpaperPath: String? { didSet { defaults.set(wallpaperPath, forKey: "wallpaperPath") } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        let defaults = UserDefaults.standard
        agent = defaults.string(forKey: "agent").flatMap(Agent.init) ?? .claude
        // Nothing chosen yet means everything is on offer.
        let savedAgents = Set((defaults.stringArray(forKey: "agents") ?? []).compactMap(Agent.init))
        agents = savedAgents.isEmpty ? Set(Agent.allCases) : savedAgents
        onboarded = defaults.bool(forKey: "onboarded")
        showsFiles = defaults.object(forKey: "showsFiles") as? Bool ?? true
        wallpaperPath = defaults.string(forKey: "wallpaperPath")
        stacks = defaults.bool(forKey: "stacks")
        bypassPermissions = defaults.bool(forKey: "bypassPermissions")
        if let saved = defaults.stringArray(forKey: "pinned") {
            pinned = saved.map { URL(fileURLWithPath: $0) }
        } else {
            let files = FileManager.default
            pinned = [.documentDirectory, .downloadsDirectory, .picturesDirectory, .applicationDirectory]
                .compactMap { files.urls(for: $0, in: $0 == .applicationDirectory ? .localDomainMask : .userDomainMask).first }
        }
    }

    var wallpaperURL: URL? {
        wallpaperPath.map { URL(fileURLWithPath: $0) }
            ?? NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    }

    /// Whether there is a picture to show: the chosen file, or the system's
    /// wallpaper, still there and readable as an image.
    var hasPicture: Bool {
        guard let url = wallpaperURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    func chooseWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use picture"
        panel.message = "Choose the picture for the top of the desktop"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            wallpaperPath = url.path
        }
    }

    func pinFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Pin"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url, !pinned.contains(url) {
            pinned.append(url)
        }
    }
}
