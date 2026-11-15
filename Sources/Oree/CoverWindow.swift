import AppKit
import SwiftUI

/// A full-screen window in the ordinary layer, for what has to take the
/// whole display for a while: first-run setup and Settings.
///
/// The desktop window lives below every app, in the wallpaper's layer, and
/// with Stage Manager on the system treats a click there as a click on the
/// wallpaper: it moves the windows aside and the click never arrives. A
/// window in the ordinary layer is clicked like any other.
final class CoverWindow: NSWindow {
    init(screen: NSScreen, @ViewBuilder content: () -> some View) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .normal
        collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        let hosting = NSHostingView(
            rootView: content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Theme.primary)
                .ignoresSafeArea()
        )
        hosting.sizingOptions = []
        contentView = hosting
        setFrame(screen.frame, display: true)
    }

    // A borderless window takes the keyboard only when it says it can.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    /// Asks for Settings on the display given as the object (its ID).
    static let oreeShowSettings = Notification.Name("OreeShowSettings")
}
