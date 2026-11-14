import SwiftUI

/// The coordinate space the whole desktop shares: the selection sweep and
/// every file icon measure themselves in it.
let desktopSpace = "desktop"

/// Where each visible file icon is, keyed by its file.
struct FramesKey: PreferenceKey {
    static let defaultValue: [URL: CGRect] = [:]

    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The icon frames, held outside view state: they change on every scrolled
/// or animated frame, and nothing should redraw because of it.
final class FrameBox {
    var frames: [URL: CGRect] = [:]
    /// When an icon last took a click. The desktop behind hears the same
    /// click and would let go of the selection the icon just made.
    var iconClicked = Date.distantPast
}

/// File icons, fetched from the system once each.
enum FileIcons {
    private static let cache = NSCache<NSURL, NSImage>()

    static func icon(for url: URL) -> NSImage {
        if let known = cache.object(forKey: url as NSURL) { return known }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: url as NSURL)
        return icon
    }
}

/// Places change by scale and opacity only, so nothing is laid out again
/// while they move.
private let travel = Animation.smooth(duration: 0.26)

/// Desktop mode: widgets first; the Files widget opens the folders, and a
/// folder opens its icons straight onto the desktop.
struct DesktopView: View {
    let store: SessionStore
    @Binding var picked: Set<URL>
    let frames: FrameBox
    let open: (AgentSession) -> Void

    private enum Place: Equatable {
        case widgets
        case folders
        /// The folder on show, after the folders opened on the way to it.
        case folder([URL])

        var depth: Int {
            switch self {
            case .widgets: 0
            case .folders: 1
            case let .folder(path): 1 + path.count
            }
        }
    }

    @State private var place = Place.widgets
    /// What is being searched for across the Mac's files.
    @State private var query = ""
    /// Whether the last move went further in, which sets the direction the
    /// places zoom.
    @State private var inward = true

    var body: some View {
        ZStack(alignment: .top) {
            switch place {
            case .widgets:
                WidgetGrid(
                    store: store,
                    showFolders: { go(.folders) },
                    showFolder: { go(.folder([$0])) }
                )
                .transition(zoom)
            case .folders:
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        BackLink(title: "Desktop") { go(.widgets) }
                        Spacer()
                        SearchField(text: $query)
                    }
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        PlacesBar { go(.folder([$0])) }
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
                                ForEach(store.roots, id: \.self) { root in
                                    FolderWidget(folder: store.folder(root)) { go(.folder([root])) }
                                }
                            }
                        }
                        .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
                    } else {
                        SearchResults(query: query, picked: $picked, frames: frames) { go(.folder([$0])) }
                    }
                }
                .transition(zoom)
            case let .folder(path):
                if let current = path.last {
                    FolderBrowser(
                        store: store,
                        folder: store.folder(current),
                        picked: $picked,
                        frames: frames,
                        parent: path.count > 1
                            ? FileManager.default.displayName(atPath: path[path.count - 2].path)
                            : "All folders",
                        enter: { go(.folder(path + [$0])) },
                        back: { go(path.count > 1 ? .folder(Array(path.dropLast())) : .folders) },
                        open: open
                    )
                    .id(current)
                    .transition(zoom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Going in, the new place grows into view and the old one grows past
    /// it; coming back, the reverse.
    private var zoom: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: inward ? 0.96 : 1.04).combined(with: .opacity),
            removal: .scale(scale: inward ? 1.04 : 0.96).combined(with: .opacity)
        )
    }

    private func go(_ next: Place) {
        inward = next.depth > place.depth
        withAnimation(travel) {
            place = next
            picked = []
        }
    }
}

/// "← All folders": the one way back from where you are.
struct BackLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                IconView(.arrowLeft)
                Text(title)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FileIcon: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Image(nsImage: FileIcons.icon(for: url))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// A folder at a glance: what arrived last. Click it to open the folder.
private struct FolderWidget: View {
    let folder: FolderModel
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    FileIcon(url: folder.url, size: 18)
                    Text(folder.name)
                        .fontWeight(.medium)
                    Text("\(folder.items.count)")
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                }
                .font(.callout)

                if folder.items.isEmpty {
                    Hint("Nothing here yet.")
                } else {
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(folder.recent) { item in
                            VStack(spacing: 6) {
                                FileIcon(url: item.url, size: 44)
                                Text(item.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A folder's icons, straight on the desktop: no frame around them. They are
/// picked the way Finder's are, can be dragged into a new order, and gather
/// into stacks by kind when that is switched on in Settings.
struct FolderBrowser: View {
    let store: SessionStore
    let folder: FolderModel
    @Binding var picked: Set<URL>
    let frames: FrameBox
    /// The name of where the back link leads.
    let parent: String
    let enter: (URL) -> Void
    let back: () -> Void
    let open: (AgentSession) -> Void
    /// The stacks spread open.
    @State private var spread: Set<FolderModel.Kind> = []
    @State private var clicks = Clicks()
    /// Only items whose names hold this show.
    @State private var filter = ""

    private var shown: [FolderModel.Item] {
        let wanted = filter.trimmingCharacters(in: .whitespaces)
        return wanted.isEmpty ? folder.items : folder.items.filter { $0.name.localizedCaseInsensitiveContains(wanted) }
    }

    /// The item being renamed, and the name as typed so far.
    @State private var renaming: URL?
    @State private var newName = ""
    @FocusState private var naming: Bool

    private var stacked: Bool { store.preferences.stacks }

    private enum Cell: Identifiable {
        case item(FolderModel.Item)
        case stack(FolderModel.Kind, [FolderModel.Item])

        var id: String {
            switch self {
            case let .item(item): item.url.path
            case let .stack(kind, _): "stack:" + kind.rawValue
            }
        }
    }

    /// With stacks on, one pile per kind, followed by its items while spread.
    private var cells: [Cell] {
        guard stacked else { return shown.map(Cell.item) }
        return FolderModel.Kind.allCases.flatMap { kind -> [Cell] in
            let members = shown.filter { $0.kind == kind }
            guard !members.isEmpty else { return [] }
            return [.stack(kind, members)] + (spread.contains(kind) ? members.map(Cell.item) : [])
        }
    }

    private var pickedHere: [URL] {
        folder.items.map(\.url).filter(picked.contains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Where back leads, and in brackets where you are.
                BackLink(title: "\(parent) (\(folder.name))", action: back)
                Spacer()
                if !pickedHere.isEmpty {
                    quickActions
                }
                SearchField(text: $filter, prompt: "Search \(folder.name)", width: 200)
            }
            // Only the icons scroll; the desktop around them stays put.
            GeometryReader { area in
            ScrollView {
                Group {
                if shown.isEmpty {
                    Hint(folder.items.isEmpty ? "This folder is empty." : "Nothing here is named like that.")
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 12) {
                        ForEach(cells) { cell in
                            switch cell {
                            case let .item(item): icon(for: item)
                            case let .stack(kind, members): pile(of: kind, members)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                }
                // The empty space around the icons is as tall as the view,
                // and a click on it lets go of the selection.
                .frame(maxWidth: .infinity, minHeight: area.size.height, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture {
                    if Date().timeIntervalSince(frames.iconClicked) > 0.2 { picked = [] }
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
            .contextMenu {
                Button("New Folder") {
                    if let made = folder.newFolder() { rename(made) }
                }
                Button("Paste", action: folder.paste)
            }
            // Files dropped here move in; with Option held, they are copied.
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                let copying = NSEvent.modifierFlags.contains(.option)
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { item, _ in
                        guard let item else { return }
                        DispatchQueue.main.async { folder.take([item], copying: copying) }
                    }
                }
                return true
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusable()
        .focusEffectDisabled()
        .onCopyCommand {
            pickedHere.map { NSItemProvider(object: $0 as NSURL) }
        }
        .onPasteCommand(of: [.fileURL]) { _ in folder.paste() }
        .onDeleteCommand {
            folder.trash(pickedHere)
            picked = []
        }
    }

    private func rename(_ item: URL) {
        picked = [item]
        newName = item.lastPathComponent
        renaming = item
        naming = true
    }

    private func commitRename() {
        if let item = renaming, let renamed = folder.rename(item, to: newName) {
            picked = [renamed]
        }
        renaming = nil
    }

    /// What can be done with the picked items in one click.
    private var quickActions: some View {
        HStack(spacing: 6) {
            Text("\(pickedHere.count) selected")
                .foregroundStyle(Theme.secondary)
            QuickAction(title: "Compress", icon: .archive) {
                folder.compress(pickedHere)
            }
            QuickAction(title: "Group", icon: .folderAdd) {
                folder.group(pickedHere)
                picked = []
            }
            QuickAction(title: "Summarise", icon: .text) {
                ask("Summarise what these items are and what is in them, briefly.")
            }
            QuickAction(title: "Rename", icon: .pencil) {
                ask("Give these items clear, consistent names based on what they contain. Tell me the old and new name of each.")
            }
            QuickAction(title: "Trash", icon: .trash) {
                folder.trash(pickedHere)
                picked = []
            }
        }
        .font(.callout)
    }

    private func ask(_ task: String) {
        open(store.start(task, about: pickedHere))
    }

    private func icon(for item: FolderModel.Item) -> some View {
        FileCell(url: item.url, name: item.name, isPicked: picked.contains(item.url), badge: nil)
            .background(GeometryReader { cell in
                Color.clear.preference(
                    key: FramesKey.self,
                    value: [item.url: cell.frame(in: .named(desktopSpace))]
                )
            })
            // One handler for both: a second click in quick succession opens.
            .onTapGesture {
                frames.iconClicked = Date()
                if clicks.isSecond(on: item.url) {
                    if item.isFolder {
                        enter(item.url)
                    } else {
                        folder.open(targets(for: item.url))
                    }
                } else {
                    pick(item.url)
                }
            }
            // A real drag: onto another icon to reorder, onto a folder to move
            // in, or out to any other app.
            .onDrag {
                if !picked.contains(item.url) { picked = [item.url] }
                DragBox.items = pickedHere.isEmpty ? [item.url] : pickedHere
                return NSItemProvider(object: item.url as NSURL)
            }
            .onDrop(of: [.fileURL], delegate: CellDrop(target: item, folder: folder))
            .overlay(alignment: .bottom) {
                if renaming == item.url {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.accent))
                        .focused($naming)
                        .onSubmit(commitRename)
                        .onExitCommand { renaming = nil }
                }
            }
            .contextMenu {
                let targets = targets(for: item.url)
                Button("Open") {
                    if item.isFolder, targets.count == 1 {
                        enter(item.url)
                    } else {
                        folder.open(targets)
                    }
                }
                if item.isFolder {
                    Button("Open in New Window") { Finder.openFolder(item.url) }
                }
                Button("Rename") { rename(item.url) }
                Button("Copy") { folder.copyToPasteboard(targets) }
                Divider()
                Button("Move to Trash", role: .destructive) {
                    folder.trash(targets)
                    picked.subtract(targets)
                }
            }
    }

    private func pile(of kind: FolderModel.Kind, _ members: [FolderModel.Item]) -> some View {
        FileCell(
            url: members[0].url,
            name: kind.rawValue,
            isPicked: spread.contains(kind),
            badge: members.count
        )
        .onTapGesture {
            frames.iconClicked = Date()
            withAnimation(travel) { spread.formSymmetricDifference([kind]) }
        }
    }

    private func pick(_ url: URL) {
        if NSEvent.modifierFlags.contains(.command) {
            picked.formSymmetricDifference([url])
        } else {
            picked = [url]
        }
    }

    /// What an action on an item applies to: the whole selection when the
    /// item is part of it, the item alone otherwise.
    private func targets(for url: URL) -> Set<URL> {
        picked.contains(url) ? Set(pickedHere) : [url]
    }
}

private struct QuickAction: View {
    let title: String
    let icon: Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconLabel(title, icon)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glass(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FileCell: View {
    let url: URL
    let name: String
    let isPicked: Bool
    /// How many items a pile holds; nil for a single item.
    let badge: Int?

    var body: some View {
        VStack(spacing: 6) {
            FileIcon(url: url, size: 56)
                .padding(6)
                .background(isPicked ? Theme.ink.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text("\(badge)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                }
            Text(name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(isPicked && badge == nil ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .frame(width: 96)
        .contentShape(Rectangle())
    }
}

/// Tells a double click from two single ones: the same icon, twice, within
/// the time the user has set for double clicks.
final class Clicks {
    private var last: (item: URL, at: Date)?

    func isSecond(on item: URL) -> Bool {
        let now = Date()
        if let last, last.item == item, now.timeIntervalSince(last.at) < NSEvent.doubleClickInterval {
            self.last = nil
            return true
        }
        last = (item, now)
        return false
    }
}

/// The items of the drag now under way, when it began in Oree: the system
/// carries one file across, and this remembers the rest of the selection.
enum DragBox {
    static var items: [URL] = []
}

/// What happens when files are dropped on an icon.
private struct CellDrop: DropDelegate {
    let target: FolderModel.Item
    let folder: FolderModel

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: NSEvent.modifierFlags.contains(.option) ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let copying = NSEvent.modifierFlags.contains(.option)
        // The right half of an icon means "after it".
        let after = info.location.x > 48
        let providers = info.itemProviders(for: [.fileURL])
        var dropped: [URL] = []
        let loading = DispatchGroup()
        for provider in providers {
            loading.enter()
            _ = provider.loadObject(ofClass: URL.self) { item, _ in
                DispatchQueue.main.async {
                    if let item { dropped.append(item) }
                    loading.leave()
                }
            }
        }
        loading.notify(queue: .main) {
            // A drag that began here brings the whole selection with it.
            let ours = !DragBox.items.isEmpty && Set(dropped).isSubset(of: Set(DragBox.items))
            let items = ours ? DragBox.items : dropped
            DragBox.items = []
            guard !items.contains(target.url) else { return }
            let here = folder.url.standardizedFileURL
            let fromHere = items.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL == here }
            if target.isFolder {
                FolderModel.bring(items, into: target.url, copying: copying)
            } else if fromHere, !copying {
                var order = folder.items.map(\.url).filter { !items.contains($0) }
                guard let index = order.firstIndex(of: target.url) else { return }
                order.insert(contentsOf: items, at: after ? index + 1 : index)
                withAnimation(travel) { folder.arrange(order) }
            } else {
                folder.take(items, copying: copying)
            }
        }
        return true
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "Search this Mac"
    var width: CGFloat = 260

    var body: some View {
        HStack(spacing: 6) {
            IconView(.search, size: 14)
                .foregroundStyle(Theme.secondary)
            TextField("Search", text: $text, prompt: Text(""))
                .textFieldStyle(.plain)
                .overlay(alignment: .leading) {
                    if text.isEmpty {
                        Text(prompt)
                            .lineLimit(1)
                            .foregroundStyle(Theme.secondary)
                            .allowsHitTesting(false)
                    }
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    IconView(.cancel, size: 12)
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(width: width)
        .glass(in: Capsule())
    }
}

/// Files and folders whose names match, found by the system's own index.
private struct SearchResults: View {
    let query: String
    @Binding var picked: Set<URL>
    let frames: FrameBox
    let showFolder: (URL) -> Void
    @State private var found: [URL] = []
    @State private var clicks = Clicks()
    @State private var searching = true

    var body: some View {
        ScrollView {
            if found.isEmpty {
                Hint(searching ? "Searching…" : "Nothing is named like that.")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 12) {
                    ForEach(found, id: \.self) { item in
                        FileCell(
                            url: item,
                            name: FileManager.default.displayName(atPath: item.path),
                            isPicked: picked.contains(item),
                            badge: nil
                        )
                        .onTapGesture {
                            frames.iconClicked = Date()
                            if clicks.isSecond(on: item) {
                                open(item)
                            } else {
                                picked = [item]
                            }
                        }
                        .onDrag { NSItemProvider(object: item as NSURL) }
                        .contextMenu {
                            Button("Open") { open(item) }
                            Button("Show in Its Folder") { showFolder(item.deletingLastPathComponent()) }
                        }
                        .help(item.deletingLastPathComponent().path)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
        // Wait for a pause in the typing before asking.
        .task(id: query) {
            searching = true
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let name = query.trimmingCharacters(in: .whitespaces)
            let lines = await Task.detached(priority: .userInitiated) {
                Shell.output("/usr/bin/mdfind", ["-name", name, "-onlyin", NSHomeDirectory()]) ?? ""
            }.value
            guard !Task.isCancelled else { return }
            found = lines.split(separator: "\n").prefix(80).map { URL(fileURLWithPath: String($0)) }
            searching = false
        }
    }

    private func open(_ item: URL) {
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: item.path, isDirectory: &isFolder), isFolder.boolValue {
            showFolder(item)
        } else {
            NSWorkspace.shared.open(item)
        }
    }
}
