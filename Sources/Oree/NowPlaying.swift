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
    /// The app the media is playing in.
    private(set) var source = ""
    private(set) var isPlaying = false
    private(set) var artwork: NSImage?
    /// The icon of the app it is playing in, shown when there is no cover.
    private(set) var sourceIcon: NSImage?
    @ObservationIgnored private var sourceBundle = ""
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var reading = false

    var hasTrack: Bool { !title.isEmpty }

    private static let folder = URL(fileURLWithPath: NSTemporaryDirectory())
    private static let reader = folder.appendingPathComponent("oree-now-playing.js")
    private static let sender = folder.appendingPathComponent("oree-media-command.js")
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
            return JSON.stringify({
                title: text("Title"), artist: text("Artist"), rate: text("PlaybackRate"),
                app: client.isNil() ? "" : ObjC.unwrap(client.displayName),
                bundle: client.isNil() ? "" : ObjC.unwrap(client.bundleIdentifier)
            });
        }
        """

    /// Sends one of the system's media commands, by number.
    private static let sendScript = """
        function run(argv) {
            \(prelude)
            ObjC.bindFunction("MRMediaRemoteSendCommand", ["bool", ["int", "id"]]);
            $.MRMediaRemoteSendCommand(parseInt(argv[0]), $());
        }
        """

    init() {
        try? Self.readScript.write(to: Self.reader, atomically: true, encoding: .utf8)
        try? Self.sendScript.write(to: Self.sender, atomically: true, encoding: .utf8)
        read()
        ticker = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.read()
        }
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
            source = ""
            isPlaying = false
            artwork = nil
            return
        }
        let changed = title != self.title
        self.title = title
        artist = item["artist"] ?? ""
        source = item["app"] ?? ""
        if let bundle = item["bundle"], bundle != sourceBundle {
            sourceBundle = bundle
            sourceIcon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
        isPlaying = (Double(item["rate"] ?? "") ?? 0) > 0
        if coverWasRead {
            artwork = cover
        } else if changed {
            // A new item: its cover is worth a second, fuller read.
            artwork = nil
            read(withCover: true)
        }
    }

    func toggle() { send(2) }
    func next() { send(4) }
    func previous() { send(5) }

    private func send(_ command: Int) {
        Task.detached(priority: .userInitiated) {
            _ = Shell.output("/usr/bin/osascript", ["-l", "JavaScript", Self.sender.path, String(command)])
            // Show the change now rather than at the next tick.
            try? await Task.sleep(for: .milliseconds(350))
            await MainActor.run { self.read() }
        }
    }
}

struct NowPlayingWidget: View {
    let playing: NowPlaying

    private static let coverSize: CGFloat = 64

    var body: some View {
        Widget(title: "Now playing", icon: .music, count: nil, height: widgetHeight) {
            if playing.hasTrack {
                VStack(spacing: 0) {
                    // What is playing: the cover, and beside it the title,
                    // who it is by and where it plays.
                    HStack(alignment: .center, spacing: 12) {
                        cover
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playing.title)
                                .font(.callout.weight(.semibold))
                                .lineLimit(2)
                            if !playing.artist.isEmpty {
                                Text(playing.artist)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                                    .lineLimit(1)
                            }
                            source
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 10)
                    // The controls, spread across the foot of the card.
                    HStack(spacing: 0) {
                        Spacer()
                        control("backward.fill", help: "Previous", action: playing.previous)
                        Spacer()
                        playButton
                        Spacer()
                        control("forward.fill", help: "Next", action: playing.next)
                        Spacer()
                    }
                }
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

    /// The app it plays in, and while it plays, a few bars moving.
    private var source: some View {
        HStack(spacing: 5) {
            if let icon = playing.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 13, height: 13)
            }
            if !playing.source.isEmpty {
                Text(playing.source)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            if playing.isPlaying {
                Bars()
            }
        }
        .padding(.top, 2)
    }

    /// The cover; without one, the icon of the app that is playing.
    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.panel)
            if let artwork = playing.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else if let icon = playing.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 42, height: 42)
            } else {
                IconView(.music, size: 24)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(width: Self.coverSize, height: Self.coverSize)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var playButton: some View {
        Button(action: playing.toggle) {
            Image(systemName: playing.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.card)
                .frame(width: 40, height: 40)
                .background(Theme.ink, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(playing.isPlaying ? "Pause" : "Play")
    }

    private func control(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Theme.primary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Three bars rising and falling, a few times a second: cheap enough to
/// leave running while something plays.
private struct Bars: View {
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * 5)
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { bar in
                    let height = still ? 6 : [4.0, 9, 6, 10, 5, 8, 3, 7][(tick + bar * 3) % 8]
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: 2, height: height)
                        .animation(.easeInOut(duration: 0.2), value: height)
                }
            }
            .frame(height: 10, alignment: .bottom)
        }
    }
}
