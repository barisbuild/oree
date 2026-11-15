import AppKit

/// A development aid: `kill -USR1 <pid>` writes a picture of each desktop
/// window to the temporary folder, so the interface can be checked without
/// screen-recording access. An app may always capture its own windows.
enum Snapshot {
    private static var source: DispatchSourceSignal?

    static func install() {
        // Off unless switched on by hand:
        // `defaults write space.oree.app debugHooks -bool true`
        guard UserDefaults.standard.bool(forKey: "debugHooks") else { return }
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler(handler: capture)
        source.resume()
        self.source = source

        // `kill -USR2`: do what the file `oree-click` in the temporary folder
        // says. "x y" clicks there, "x y 2" double-clicks, measured from the
        // top left of the first desktop window; "type words" types them.
        signal(SIGUSR2, SIG_IGN)
        let clicks = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        clicks.setEventHandler(handler: click)
        clicks.resume()
        clickSource = clicks
    }

    private static var clickSource: DispatchSourceSignal?

    /// The desktop window of the main display. The order of the app's
    /// windows changes as they take turns being key, so it is found by place.
    private static var mainDesktop: NSWindow? {
        NSApp.windows.first { $0 is DesktopWindow && $0.frame.origin == .zero }
    }

    private static func click() {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oree-click")
        let request = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        // "film": record the scripted demo (see Film).
        if request.hasPrefix("film"), let window = Self.mainDesktop {
            MainActor.assumeIsolated { Film.run(in: window) }
            return
        }
        // "type some words": put the words in the focused field and press Return.
        // "fill some words": the same without Return.
        if request.hasPrefix("type ") || request.hasPrefix("fill ") {
            let words = request.dropFirst(5).trimmingCharacters(in: .newlines)
            let submit = request.hasPrefix("type ")
            NSApp.activate(ignoringOtherApps: true)
            Self.mainDesktop?.makeKey()
            // Give the window a moment to become key and focus its field.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // Another app may have kept the front: focus the field directly.
                if let window = Self.mainDesktop, !(window.firstResponder is NSTextView) {
                    let field = MainActor.assumeIsolated { Film.firstField(in: window.contentView) }
                    if let field { window.makeFirstResponder(field) }
                }
                let editor = Self.mainDesktop?.firstResponder as? NSTextView
                editor?.insertText(words, replacementRange: editor?.selectedRange() ?? NSRange())
                guard submit else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    editor?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                }
            }
            return
        }
        let numbers = request
            .split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
        guard numbers.count >= 2, let window = Self.mainDesktop else { return }
        let point = NSPoint(x: numbers[0], y: window.frame.height - numbers[1])
        for count in 1...(numbers.count > 2 ? Int(numbers[2]) : 1) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1
                ) else { continue }
                // Queued, not sent: a view tracking the mouse reads the queue.
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    private static func capture() {
        // Looked up by name: the Swift interface no longer offers it.
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        let onlyThisWindow: UInt32 = 1 << 3
        let nominalResolution: UInt32 = 1 << 4
        let windows = NSApp.windows.filter { $0 is DesktopWindow }.sorted { $0.frame.minX < $1.frame.minX }
        for (index, window) in windows.enumerated() {
            guard let image = capture(.null, onlyThisWindow, UInt32(window.windowNumber), nominalResolution)?
                .takeRetainedValue() else { continue }
            let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oree-\(index).png")
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
        }
    }
}
