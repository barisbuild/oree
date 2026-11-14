import AppKit
import SwiftUI

/// Drag across empty space to pick every icon the rectangle touches, the way
/// it is done on Finder's desktop. Command adds to what is already picked.
struct Sweep: ViewModifier {
    @Binding var picked: Set<URL>
    let frames: FrameBox
    /// The rectangle while one is being dragged out.
    @State private var area: CGRect?
    /// What was picked when a Command-drag began.
    @State private var kept: Set<URL> = []

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onPreferenceChange(FramesKey.self) { [frames] in frames.frames = $0 }
            // Only a click on empty space lets go of the selection.
            .onTapGesture {
                if Date().timeIntervalSince(frames.iconClicked) > 0.2 { picked = [] }
            }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(desktopSpace))
                    .onChanged { drag in
                        guard !isOnIcon(drag.startLocation) else { return }
                        if area == nil {
                            kept = NSEvent.modifierFlags.contains(.command) ? picked : []
                        }
                        let swept = CGRect(
                            x: min(drag.startLocation.x, drag.location.x),
                            y: min(drag.startLocation.y, drag.location.y),
                            width: abs(drag.location.x - drag.startLocation.x),
                            height: abs(drag.location.y - drag.startLocation.y)
                        )
                        area = swept
                        picked = kept.union(frames.frames.filter { $0.value.intersects(swept) }.keys)
                    }
                    .onEnded { _ in area = nil }
            )
            .overlay {
                if let area {
                    Rectangle()
                        .fill(Theme.ink.opacity(0.12))
                        .overlay(Rectangle().strokeBorder(Theme.ink.opacity(0.55)))
                        .frame(width: area.width, height: area.height)
                        .position(x: area.midX, y: area.midY)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: desktopSpace)
    }
}

extension Sweep {
    private func isOnIcon(_ point: CGPoint) -> Bool {
        frames.frames.values.contains { $0.contains(point) }
    }
}

/// The places a file manager starts from: home, iCloud, applications, the
/// Trash, and every disk, each of the removable ones with a way to eject it.
struct PlacesBar: View {
    let open: (URL) -> Void
    @State private var disks: [Disk] = []

    private struct Disk: Identifiable {
        let url: URL
        let name: String
        let ejectable: Bool
        var id: URL { url }
    }

    private struct Place: Identifiable {
        let name: String
        let icon: Icon
        let url: URL
        var id: URL { url }
    }

    private var places: [Place] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return [
            Place(name: "Home", icon: .home, url: home),
            Place(name: "iCloud Drive", icon: .cloud, url: cloud),
            Place(name: "Applications", icon: .folder, url: URL(fileURLWithPath: "/Applications")),
            Place(name: "Trash", icon: .trash, url: home.appendingPathComponent(".Trash")),
        ].filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(places) { place in
                    chip(place.name, place.icon) { open(place.url) }
                }
                ForEach(disks) { disk in
                    HStack(spacing: 2) {
                        chip(disk.name, .drive) { open(disk.url) }
                        if disk.ejectable {
                            Button {
                                try? NSWorkspace.shared.unmountAndEjectDevice(at: disk.url)
                            } label: {
                                IconView(.arrowUp, size: 13)
                                    .frame(width: 26, height: 26)
                                    .glass(in: Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Eject \(disk.name)")
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
        .onAppear(perform: readDisks)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in readDisks() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in readDisks() }
    }

    private func chip(_ name: String, _ icon: Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconLabel(name, icon)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glass(in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func readDisks() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        disks = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: .skipHiddenVolumes) ?? [])
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return Disk(
                    url: url,
                    name: values?.volumeName ?? url.lastPathComponent,
                    ejectable: values?.volumeIsEjectable == true || values?.volumeIsRemovable == true
                        || values?.volumeIsInternal == false
                )
            }
    }
}
