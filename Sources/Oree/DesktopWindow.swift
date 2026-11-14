import AppKit
import SwiftUI

/// What the system leaves free on one display: the room around the menu
/// bar and the Dock. It changes when the Dock moves or hides, and the
/// interface follows without the window being made again.
@Observable
final class ScreenSpace {
    var insets: EdgeInsets

    init(_ screen: NSScreen) {
        insets = Self.insets(of: screen)
    }

    static func insets(of screen: NSScreen) -> EdgeInsets {
        let frame = screen.frame
        let free = screen.visibleFrame
        return EdgeInsets(
            top: frame.maxY - free.maxY,
            leading: free.minX - frame.minX,
            bottom: free.minY - frame.minY,
            trailing: frame.maxX - free.maxX
        )
    }
}

/// A borderless, opaque window in the wallpaper's own layer. With Finder's
/// desktop off (`defaults write com.apple.finder CreateDesktop -bool false`)
/// nothing sits between it and the user: it is the desktop.
final class DesktopWindow: NSWindow {
    /// The display this window is the desktop of.
    let display: CGDirectDisplayID
    private let space: ScreenSpace

    init(screen: NSScreen, @ViewBuilder content: (ScreenSpace) -> some View) {
        display = screen.displayID
        space = ScreenSpace(screen)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        backgroundColor = NSColor(Theme.ground)

        // The window covers the whole display, menu bar and Dock included:
        // the picture runs edge to edge, the interface keeps to what is free.
        let hosting = NSHostingView(
            rootView: content(space)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.ground)
                .foregroundStyle(Theme.primary)
                .ignoresSafeArea()
        )
        // The window is the size of its display, whatever the content would
        // like to be.
        hosting.sizingOptions = []
        contentView = hosting
        setFrame(screen.frame, display: true)
        orderFront(nil)
    }

    /// Take the display's new size and free room, in place.
    func follow(_ screen: NSScreen) {
        if frame != screen.frame {
            setFrame(screen.frame, display: true)
        }
        let insets = ScreenSpace.insets(of: screen)
        if insets != space.insets {
            withAnimation(.smooth(duration: 0.3)) { space.insets = insets }
        }
    }

    // Borderless windows refuse key status by default; the composer needs it.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
