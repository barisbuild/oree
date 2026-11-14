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

    private static let coverSize: CGFloat = 104

    var body: some View {
        Widget(title: "Now playing", icon: .music, count: nil, height: widgetHeight) {
            if playing.hasTrack {
                // The cover and the column beside it are one height: the
                // words hang from its top edge, the buttons sit on its foot.
                HStack(alignment: .top, spacing: 14) {
                    cover
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playing.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text([playing.artist, playing.source].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            control(.arrowLeft, help: "Previous", action: playing.previous)
                            control(playing.isPlaying ? .pause : .play, help: playing.isPlaying ? "Pause" : "Play", prominent: true, action: playing.toggle)
                            control(.arrowRight, help: "Next", action: playing.next)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Self.coverSize)
                }
                .frame(maxHeight: .infinity)
            } else {
                Hint("Play a song or a video in any app and it shows here.")
            }
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
                IconView(.music, size: 28)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(width: Self.coverSize, height: Self.coverSize)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func control(_ icon: Icon, help: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconView(icon, size: 16)
                .frame(width: 34, height: 34)
                .background(prominent ? Theme.panel : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
