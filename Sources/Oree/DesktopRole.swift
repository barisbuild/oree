import AppKit
import Observation
import ServiceManagement
import UniformTypeIdentifiers

/// Whether Oree stands in for the Mac's desktop: started at login by the
/// system, started again if it ever stops unasked, with Finder's own desktop
/// switched off. Finder itself keeps working.
@Observable
final class DesktopRole {
    private static let agent = SMAppService.agent(plistName: "space.oree.agent.plist")
    private static let bundle = Bundle.main.bundleIdentifier ?? ""

    /// This copy was started by the system as the desktop, not opened by hand.
    static let isTheDesktop = ProcessInfo.processInfo.environment["OREE_AGENT"] != nil

    private(set) var isOn = DesktopRole.agent.status == .enabled
    /// Why the role could not be taken, in the system's words.
    private(set) var problem: String?

    /// There is only ever one Oree. The system's copy takes over from one
    /// opened by hand; a copy opened by hand steps aside for any other.
    static func settleWithOtherCopies() {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
            .filter { $0 != .current }
        guard !others.isEmpty else { return }
        if isTheDesktop {
            others.forEach { $0.terminate() }
        } else {
            exit(0)
        }
    }

    func turnOn() {
        if Self.agent.status != .enabled {
            do {
                try Self.agent.register()
            } catch {
                problem = error.localizedDescription
                return
            }
        }
        problem = nil
        isOn = true
        Self.finderDesktop(shown: false)
        Self.fileViewer(isOree: true)
        // The system now starts its own copy, which takes over from this one.
    }

    /// Give the desktop back to Finder and leave.
    func turnOff() {
        Self.finderDesktop(shown: true)
        Self.fileViewer(isOree: false)
        try? Self.agent.unregister()
        exit(0)
    }

    /// Register Oree as the system's file viewer while it is the desktop.
    private static func fileViewer(isOree: Bool) {
        _ = Shell.output("/usr/bin/defaults", isOree
            ? ["write", "-g", "NSFileViewer", "-string", bundle]
            : ["delete", "-g", "NSFileViewer"])
        let app = isOree ? Bundle.main.bundleURL : Finder.app
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.setDefaultApplication(at: app, toOpen: .folder) { _ in done.signal() }
        _ = done.wait(timeout: .now() + 5)
    }

    private static func finderDesktop(shown: Bool) {
        // Finder restarts to take the change; leave it be when there is none.
        let hidden = Shell.output("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "0"
        guard hidden == shown else { return }
        _ = Shell.output("/usr/bin/defaults", shown
            ? ["delete", "com.apple.finder", "CreateDesktop"]
            : ["write", "com.apple.finder", "CreateDesktop", "-bool", "false"])
        _ = Shell.output("/usr/bin/killall", ["Finder"])
    }
}
