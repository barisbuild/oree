import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [DesktopWindow] = []
    private let store = SessionStore()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(reveal(_:reply:)),
            forEventClass: Finder.revealClass,
            andEventID: Finder.revealEvent
        )
    }

    /// Open folders and show files in Finder when another app calls Oree.
    func application(_ application: NSApplication, open urls: [URL]) {
        var files: [URL] = []
        for url in urls where url.isFileURL {
            if Finder.isFolder(url) {
                Finder.openFolder(url)
            } else {
                files.append(url)
            }
        }
        Finder.reveal(files)
    }

    @objc private func reveal(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let target = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        let entries = target.descriptorType == typeAEList
            ? (0..<target.numberOfItems).compactMap { target.atIndex($0 + 1) }
            : [target]
        Finder.reveal(entries.compactMap { $0.coerce(toDescriptorType: typeFileURL)?.fileURLValue })
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMenu()
        Snapshot.install()
        store.keepFresh()
        arrangeWindows()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.arrangeWindows()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopAll()
    }

    /// One window per display, each a full desktop of its own: the same
    /// agents and data, its own place in them.
    ///
    /// The system reports a change whenever the Dock moves to another
    /// display or a display's size changes. A window whose display is still
    /// there is kept and only told its new free room; making it again would
    /// blank the desktop for a moment. Windows are opened and closed only as
    /// displays come and go.
    private func arrangeWindows() {
        let screens = NSScreen.screens
        let present = Set(screens.map(\.displayID))
        windows.filter { !present.contains($0.display) }.forEach { $0.close() }
        windows.removeAll { !present.contains($0.display) }
        for screen in screens {
            if let window = windows.first(where: { $0.display == screen.displayID }) {
                window.follow(screen)
            } else {
                windows.append(DesktopWindow(screen: screen) { space in
                    RootView(store: store, space: space)
                })
            }
        }
    }

    /// An accessory app shows no menu bar of its own, but text fields still
    /// find Cut/Copy/Paste and Quit through the main menu's key equivalents.
    private static func makeMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        // A desktop is not quit with Command-Q, any more than Finder's is;
        // Settings is where the role is given up.
        if !DesktopRole.isTheDesktop {
            appMenu.addItem(withTitle: "Quit Oree", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        }
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        return main
    }
}
