import AppKit

/// A development aid for making a short screen recording of the desktop
/// without screen-recording access: the app captures its own window thirty
/// times a second, draws the pointer onto each frame itself, and moves that
/// pointer, clicks and types to a script. Only with the debug hooks on:
/// write "film" to the `oree-click` file and send USR2. Frames and a
/// timing list land in `oree-film` in the temporary folder.
@MainActor
enum Film {
    private static var recording = false

    static func run(in window: NSWindow) {
        guard !recording else { return }
        recording = true
        Task { @MainActor in
            await play(in: window)
            recording = false
        }
    }

    // MARK: The script

    private static func play(in window: NSWindow) async {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        let recorder = Recorder(window: window)
        var pointer = CGPoint(x: 1180, y: 800)
        recorder.pointer = pointer
        recorder.start()

        func hold(_ seconds: Double) async {
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
        }
        /// A hand's movement: eased, with a slight bow.
        func glide(to target: CGPoint, over seconds: Double) async {
            let from = pointer
            let steps = max(1, Int(seconds * 60))
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
                let bow = sin(t * .pi) * 18
                pointer = CGPoint(
                    x: from.x + (target.x - from.x) * eased,
                    y: from.y + (target.y - from.y) * eased - bow
                )
                recorder.pointer = pointer
                await hold(1.0 / 60)
            }
        }
        func click() {
            let point = NSPoint(x: pointer.x, y: window.frame.height - pointer.y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                ) else { continue }
                NSApp.postEvent(event, atStart: false)
            }
        }

        await hold(0.25)
        await glide(to: CGPoint(x: 640, y: 446), over: 0.7)
        click()
        await hold(0.3)
        // If the system kept another app in front, the click focuses
        // nothing: put the field in charge of the typing directly.
        if !(window.firstResponder is NSTextView), let field = Self.firstField(in: window.contentView) {
            window.makeFirstResponder(field)
        }
        // Typed the way a person types: not quite evenly.
        for letter in "tidy my downloads by month" {
            (window.firstResponder as? NSTextView)?.insertText(String(letter), replacementRange: NSRange(location: NSNotFound, length: 0))
            await hold(0.03 + Double.random(in: 0...0.03))
        }
        await hold(0.25)
        (window.firstResponder as? NSTextView)?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        // The pointer eases off while the agent works.
        await glide(to: CGPoint(x: 760, y: 360), over: 0.8)
        await hold(1.5)
        // And back to the desktop, everything in view.
        await glide(to: CGPoint(x: 492, y: 62), over: 0.7)
        click()
        await hold(0.8)
        await recorder.stop()
    }

    /// The first editable text field in a view's tree: the task box.
    static func firstField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for child in view.subviews {
            if let found = firstField(in: child) { return found }
        }
        return nil
    }

    // MARK: Frames

    /// Captures the window on a queue of its own, so the interface keeps its
    /// pace, and writes the frames on others.
    private final class Recorder: @unchecked Sendable {
        private let windowNumber: CGWindowID
        private let frameHeight: CGFloat
        private let folder: URL
        private let lock = NSLock()
        private var _pointer = CGPoint.zero
        private var running = false
        private var times: [(Int, Double)] = []
        private let writers = OperationQueue()
        private let arrow: CGImage?
        private let hotSpot: CGPoint

        var pointer: CGPoint {
            get { lock.withLock { _pointer } }
            set { lock.withLock { _pointer = newValue } }
        }

        init(window: NSWindow) {
            windowNumber = CGWindowID(window.windowNumber)
            frameHeight = window.frame.height
            folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oree-film")
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            writers.maxConcurrentOperationCount = 4
            let cursor = NSCursor.arrow
            var rect = CGRect(origin: .zero, size: cursor.image.size)
            arrow = cursor.image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            hotSpot = cursor.hotSpot
        }

        func start() {
            running = true
            Thread.detachNewThread { [self] in loop() }
        }

        func stop() async {
            lock.withLock { running = false }
            try? await Task.sleep(for: .milliseconds(200))
            await withCheckedContinuation { done in writers.addBarrierBlock { done.resume() } }
            // A list ffmpeg's concat reader takes, each frame held until the next.
            let list = times.indices.map { index in
                let (number, time) = times[index]
                let next = index + 1 < times.count ? times[index + 1].1 : time + 1.0 / 30
                return "file 'f\(String(format: "%05d", number)).jpg'\nduration \(String(format: "%.4f", next - time))"
            }.joined(separator: "\n")
            try? list.write(to: folder.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
        }

        private func loop() {
            typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
            guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
            let capture = unsafeBitCast(symbol, to: Capture.self)
            let began = CFAbsoluteTimeGetCurrent()
            var number = 0
            while lock.withLock({ running }) {
                let frameStart = CFAbsoluteTimeGetCurrent()
                // This window alone, at full resolution.
                if let image = capture(.null, 1 << 3, windowNumber, 1 << 3)?.takeRetainedValue() {
                    number += 1
                    let frame = number
                    let at = pointer
                    times.append((frame, frameStart - began))
                    writers.addOperation { [self] in write(image, pointer: at, number: frame) }
                }
                let spent = CFAbsoluteTimeGetCurrent() - frameStart
                if spent < 1.0 / 30 { Thread.sleep(forTimeInterval: 1.0 / 30 - spent) }
            }
        }

        private func write(_ image: CGImage, pointer: CGPoint, number: Int) {
            let scale = CGFloat(image.height) / frameHeight
            guard let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            if let arrow {
                let size = CGSize(width: CGFloat(arrow.width) / CGFloat(arrow.height) * 25 * scale, height: 25 * scale)
                let origin = CGPoint(
                    x: (pointer.x - hotSpot.x) * scale,
                    y: CGFloat(image.height) - (pointer.y - hotSpot.y) * scale - size.height
                )
                context.draw(arrow, in: CGRect(origin: origin, size: size))
            }
            guard let drawn = context.makeImage(),
                  let data = NSBitmapImageRep(cgImage: drawn).representation(using: .jpeg, properties: [.compressionFactor: 0.93])
            else { return }
            try? data.write(to: folder.appendingPathComponent("f\(String(format: "%05d", number)).jpg"))
        }
    }
}
