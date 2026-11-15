import AppKit
import Observation
import SwiftUI

/// Whatever is playing on this Mac, in any app: a song in a music player, a
/// video in a browser. It is the same information Control Centre shows.
///
/// The system only answers its own programs, so the question is put through
/// `osascript`, which is one. That rests on a private part of macOS and may
/// stop working with an update; the widget then simply stays empty.
@Observable
final class NowPlaying {
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    /// How long the item runs, in seconds; zero when the app does not say.
    private(set) var duration: Double = 0
    /// How far in it was when last read, and when that was.
    @ObservationIgnored private var elapsed: Double = 0
    @ObservationIgnored private var readAt = Date()
    /// Covers looked up from the store, by item, and the item now wanted.
    @ObservationIgnored private var covers: [String: NSImage] = [:]
    @ObservationIgnored private var wanted = ""
    /// The app the media is playing in.
    private(set) var source = ""
    private(set) var isPlaying = false
    private(set) var artwork: NSImage?
    /// The icon of the app it is playing in, shown when there is no cover.
    private(set) var sourceIcon: NSImage?
    @ObservationIgnored private var sourceBundle = ""
    @ObservationIgnored private var watcher: Process?
    @ObservationIgnored private var reading = false

    var hasTrack: Bool { !title.isEmpty }

    private static let folder = URL(fileURLWithPath: NSTemporaryDirectory())
    private static let reader = folder.appendingPathComponent("oree-now-playing.js")
    private static let watch = folder.appendingPathComponent("oree-now-playing-watch.js")
    private static let cover = folder.appendingPathComponent("oree-now-playing-cover")

    private static let prelude = """
        ObjC.import("Foundation");
        $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework").load;
        """

    /// Prints the playing item as JSON, or nothing. Given a path, it also
    /// writes the item's cover there.
    private static let readScript = """
        function run(argv) {
            \(prelude)
            var request = $.NSClassFromString("MRNowPlayingRequest");
            var item = request.localNowPlayingItem;
            if (item.isNil()) return "";
            var info = item.nowPlayingInfo;
            function text(key) {
                var value = info.valueForKey("kMRMediaRemoteNowPlayingInfo" + key);
                return value.isNil() ? "" : ObjC.unwrap(value.description);
            }
            if (argv.length > 0) {
                var art = info.valueForKey("kMRMediaRemoteNowPlayingInfoArtworkData");
                if (!art.isNil()) art.writeToFileAtomically(argv[0], true);
            }
            var client = request.localNowPlayingPlayerPath.client;
            var stamp = info.valueForKey("kMRMediaRemoteNowPlayingInfoTimestamp");
            return JSON.stringify({
                title: text("Title"), artist: text("Artist"), album: text("Album"), rate: text("PlaybackRate"),
                elapsed: text("ElapsedTime"), duration: text("Duration"),
                store: text("AlbumiTunesStoreAdamIdentifier") || text("iTunesStoreSubscriptionAdamIdentifier") || text("iTunesStoreIdentifier"),
                stamp: stamp.isNil() ? "" : String(stamp.timeIntervalSince1970),
                app: client.isNil() ? "" : ObjC.unwrap(client.displayName),
                bundle: client.isNil() ? "" : ObjC.unwrap(client.bundleIdentifier)
            });
        }
        """

    /// Stays running and writes a line of JSON, as the reader does, each
    /// time what is playing changes: paused from the keyboard or earbuds,
    /// a new song, moved along. Nothing playing writes "{}".
    private static let watchScript = """
        function run() {
            \(prelude)
            var request = $.NSClassFromString("MRNowPlayingRequest");
            var out = $.NSFileHandle.fileHandleWithStandardOutput;
            var last = null;
            for (;;) {
                var line = "{}";
                var item = request.localNowPlayingItem;
                if (!item.isNil()) {
                    var info = item.nowPlayingInfo;
                    var text = function (key) {
                        var value = info.valueForKey("kMRMediaRemoteNowPlayingInfo" + key);
                        return value.isNil() ? "" : ObjC.unwrap(value.description);
                    };
                    var client = request.localNowPlayingPlayerPath.client;
                    var stamp = info.valueForKey("kMRMediaRemoteNowPlayingInfoTimestamp");
                    line = JSON.stringify({
                        title: text("Title"), artist: text("Artist"), album: text("Album"), rate: text("PlaybackRate"),
                        elapsed: text("ElapsedTime"), duration: text("Duration"),
                        store: text("AlbumiTunesStoreAdamIdentifier") || text("iTunesStoreSubscriptionAdamIdentifier") || text("iTunesStoreIdentifier"),
                        stamp: stamp.isNil() ? "" : String(stamp.timeIntervalSince1970),
                        app: client.isNil() ? "" : ObjC.unwrap(client.displayName),
                        bundle: client.isNil() ? "" : ObjC.unwrap(client.bundleIdentifier)
                    });
                }
                if (line !== last) {
                    out.writeData($(line + "\\n").dataUsingEncoding($.NSUTF8StringEncoding));
                    last = line;
                }
                delay(0.3);
            }
        }
        """

    /// The system's media commands, called in this process: sending, unlike
    /// reading, needs no help from an Apple program, so it is immediate.
    private static let remote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias SetElapsed = @convention(c) (Double) -> Void
    private static let sendCommand = dlsym(remote, "MRMediaRemoteSendCommand").map { unsafeBitCast($0, to: SendCommand.self) }
    private static let setElapsed = dlsym(remote, "MRMediaRemoteSetElapsedTime").map { unsafeBitCast($0, to: SetElapsed.self) }

    init() {
        // A recording may show what is really playing, with the rest made up:
        // `defaults write space.oree.app demoLiveMusic -bool true`.
        if Demo.on && !UserDefaults.standard.bool(forKey: "demoLiveMusic") {
            title = "Low Tide"
            artist = "Halden"
            album = "Shorelines"
            duration = 214
            elapsed = 61
            readAt = Date()
            source = "Music"
            isPlaying = true
            sourceIcon = NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app")
            artwork = Self.demoCover()
            return
        }
        try? Self.readScript.write(to: Self.reader, atomically: true, encoding: .utf8)
        try? Self.watchScript.write(to: Self.watch, atomically: true, encoding: .utf8)
        startWatching()
    }

    /// Run the watching script and take each line it writes. Should it ever
    /// stop, it is started again.
    private func startWatching() {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", Self.watch.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var pending = Data()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                let item = (try? JSONSerialization.jsonObject(with: line)) as? [String: String]
                DispatchQueue.main.async { self?.take(item, cover: nil, coverWasRead: false) }
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.startWatching() }
        }
        watcher = process
        try? process.run()
    }

    private func read(withCover: Bool = false) {
        guard !reading else { return }
        reading = true
        Task.detached(priority: .utility) {
            if withCover { try? FileManager.default.removeItem(at: Self.cover) }
            let output = Shell.output(
                "/usr/bin/osascript",
                ["-l", "JavaScript", Self.reader.path] + (withCover ? [Self.cover.path] : [])
            ) ?? ""
            let item = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [String: String]
            let cover = withCover ? NSImage(contentsOf: Self.cover) : nil
            await MainActor.run {
                self.reading = false
                self.take(item, cover: cover, coverWasRead: withCover)
            }
        }
    }

    private func take(_ item: [String: String]?, cover: NSImage?, coverWasRead: Bool) {
        guard let item, let title = item["title"], !title.isEmpty else {
            self.title = ""
            artist = ""
            album = ""
            duration = 0
            source = ""
            isPlaying = false
            artwork = nil
            return
        }
        let changed = title != self.title
        self.title = title
        artist = item["artist"] ?? ""
        album = item["album"] ?? ""
        source = item["app"] ?? ""
        duration = Double(item["duration"] ?? "") ?? 0
        elapsed = Double(item["elapsed"] ?? "") ?? 0
        readAt = Double(item["stamp"] ?? "").map { Date(timeIntervalSince1970: $0) } ?? Date()
        if let bundle = item["bundle"], bundle != sourceBundle {
            sourceBundle = bundle
            sourceIcon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
        isPlaying = (Double(item["rate"] ?? "") ?? 0) > 0
        if coverWasRead {
            artwork = cover
            // Apple Music sends no cover of its own, only the item's number
            // in its store: the store's public lookup has the picture.
            // Songs from one album share a cover: looked up once, kept.
            if cover == nil, let store = item["store"], !store.isEmpty {
                wanted = store
                if let known = covers[store] { artwork = known } else { lookUpCover(store) }
            }
        } else if changed {
            // A new item: its cover is worth a second, fuller read.
            artwork = nil
            read(withCover: true)
        }
    }

    /// A made-up cover: a deep blue sky with a low sun.
    private static func demoCover() -> NSImage {
        NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
            NSGradient(colors: [
                NSColor(red: 0.98, green: 0.62, blue: 0.42, alpha: 1),
                NSColor(red: 0.55, green: 0.33, blue: 0.62, alpha: 1),
                NSColor(red: 0.12, green: 0.14, blue: 0.42, alpha: 1),
            ])?.draw(in: rect, angle: 90)
            NSColor(red: 1, green: 0.85, blue: 0.62, alpha: 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: 230, y: 150, width: 140, height: 140)).fill()
            return true
        }
    }

    private func lookUpCover(_ store: String) {
        Task.detached(priority: .utility) {
            guard let lookup = URL(string: "https://itunes.apple.com/lookup?id=\(store)"),
                  let (data, _) = try? await URLSession.shared.data(from: lookup),
                  let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let small = (reply["results"] as? [[String: Any]])?.first?["artworkUrl100"] as? String,
                  let large = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb")),
                  let (picture, _) = try? await URLSession.shared.data(from: large),
                  let image = NSImage(data: picture)
            else { return }
            await MainActor.run {
                self.covers[store] = image
                // Still the same item: set its cover.
                if self.wanted == store { self.artwork = image }
            }
        }
    }

    func toggle() {
        // Shown at once; the next reading confirms it.
        isPlaying.toggle()
        if Demo.on { return }
        send(2)
    }
    func next() { send(4) }

    /// How far into the item it is now, reckoned from the last reading.
    func position(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        let moved = isPlaying ? date.timeIntervalSince(readAt) : 0
        return min(duration, max(0, elapsed + moved))
    }

    /// Bring the app that is playing to the front.
    func openSource() {
        guard !sourceBundle.isEmpty,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: sourceBundle)
        else { return }
        NSWorkspace.shared.open(app)
    }

    /// Move the playing item to a point, in seconds.
    func seek(to seconds: Double) {
        elapsed = seconds
        readAt = Date()
        if Demo.on { return }
        Self.setElapsed?(seconds)
    }
    func previous() { send(5) }

    /// The watcher reports what comes of it.
    private func send(_ command: Int32) {
        _ = Self.sendCommand?(command, nil)
    }
}

struct NowPlayingWidget: View {
    let playing: NowPlaying

    private static let coverSize: CGFloat = 132

    var body: some View {
        Widget(
            title: "Now playing", icon: .music, count: nil, height: widgetHeight,
            accessory: playing.hasTrack ? AnyView(source) : nil
        ) {
            if playing.hasTrack {
                // A large cover, and beside it, hanging from its top edge,
                // the title, who it is by and where it plays; the controls
                // sit on its foot.
                HStack(alignment: .top, spacing: 14) {
                    cover
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playing.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                        if !playing.artist.isEmpty || !playing.album.isEmpty {
                            Text([playing.artist, playing.album].filter { !$0.isEmpty }.joined(separator: " — "))
                                .font(.callout)
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if playing.duration > 0 {
                            Progress(playing: playing)
                        }
                        // As Apple draws them: bare symbols, the middle one larger.
                        HStack(spacing: 0) {
                            control("backward.fill", size: 17, help: "Previous", action: playing.previous)
                            Spacer(minLength: 0)
                            control(playing.isPlaying ? "pause.fill" : "play.fill", size: 24,
                                    help: playing.isPlaying ? "Pause" : "Play", action: playing.toggle)
                            Spacer(minLength: 0)
                            control("forward.fill", size: 17, help: "Next", action: playing.next)
                        }
                        .padding(.horizontal, -6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: Self.coverSize, alignment: .leading)
                }
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 42, height: 42)
                        .background(Theme.panel, in: Circle())
                    Text("Nothing playing")
                        .font(.callout.weight(.medium))
                    Text("Play a song or a video in any app and it shows here.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The app it plays in, across from the title: its icon alone.
    @ViewBuilder
    private var source: some View {
        if let icon = playing.sourceIcon {
            Button(action: playing.openSource) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Open \(playing.source)")
        }
    }

    /// The cover; without one, the icon of the app that is playing.
    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.panel)
            if let artwork = playing.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else if let icon = playing.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            } else {
                IconView(.music, size: 32)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(width: Self.coverSize, height: Self.coverSize)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    private func control(_ symbol: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(Theme.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// How far through the item is, as a thin bar with the time on either
/// side; dragged, it moves the item to that point.
private struct Progress: View {
    let playing: NowPlaying
    /// Where the hand has it while dragging, 0 to 1.
    @State private var dragging: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: playing.isPlaying ? 0.5 : 60)) { context in
            let share = dragging ?? playing.position(at: context.date) / playing.duration
            VStack(spacing: 3) {
                GeometryReader { bar in
                    Capsule()
                        .fill(Theme.panel)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Theme.secondary)
                                .frame(width: max(4, bar.size.width * share))
                        }
                        .frame(height: dragging == nil ? 4 : 6)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in dragging = min(1, max(0, drag.location.x / bar.size.width)) }
                                .onEnded { _ in
                                    if let dragging { playing.seek(to: dragging * playing.duration) }
                                    dragging = nil
                                }
                        )
                }
                .frame(height: 10)
                HStack {
                    Text(Self.clock(share * playing.duration))
                    Spacer()
                    Text("-" + Self.clock((1 - share) * playing.duration))
                }
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(Theme.secondary)
            }
            .animation(.smooth(duration: 0.15), value: dragging == nil)
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
