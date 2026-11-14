import AppKit
import Observation
import UniformTypeIdentifiers

/// One folder's contents, kept current as the folder changes.
@Observable
final class FolderModel: Identifiable {
    /// What a stack gathers.
    enum Kind: String, CaseIterable, Identifiable {
        case folders = "Folders"
        case images = "Images"
        case pdfs = "PDFs"
        case documents = "Documents"
        case media = "Media"
        case archives = "Archives"
        case other = "Other"
        var id: Self { self }
    }

    struct Item: Identifiable, Hashable {
        let url: URL
        let kind: Kind
        /// When it arrived in the folder.
        let added: Date
        var id: URL { url }
        var name: String { FileManager.default.displayName(atPath: url.path) }
        var isFolder: Bool { kind == .folders }
    }

    let url: URL
    private(set) var items: [Item] = []
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?

    var id: URL { url }
    var name: String { FileManager.default.displayName(atPath: url.path) }

    /// The newest arrivals, for the folder's widget.
    var recent: [Item] {
        Array(items.sorted { $0.added > $1.added }.prefix(4))
    }

    init(url: URL) {
        self.url = url
        reload()
        // The folder's own entry changes when something is added, removed or
        // renamed in it.
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        watcher.setEventHandler { [weak self] in self?.reload() }
        watcher.setCancelHandler { Darwin.close(descriptor) }
        watcher.resume()
        self.watcher = watcher
    }

    deinit {
        watcher?.cancel()
    }

    func reload() {
        let keys: Set<URLResourceKey> = [
            .contentTypeKey, .isDirectoryKey, .isPackageKey,
            .addedToDirectoryDateKey, .contentModificationDateKey,
        ]
        let found = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles
        )) ?? []
        // The user's own arrangement first, in its order; the rest by name.
        let place = Dictionary(uniqueKeysWithValues: arrangement.enumerated().map { ($1, $0) })
        items = found
            .map { entry in
                let values = try? entry.resourceValues(forKeys: keys)
                return Item(
                    url: entry,
                    kind: Self.kind(of: values),
                    added: values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast
                )
            }
            .sorted { first, second in
                switch (place[first.url.lastPathComponent], place[second.url.lastPathComponent]) {
                case let (a?, b?): a < b
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil):
                    first.url.lastPathComponent.localizedStandardCompare(second.url.lastPathComponent) == .orderedAscending
                }
            }
    }

    private static func kind(of values: URLResourceValues?) -> Kind {
        if values?.isDirectory == true, values?.isPackage != true { return .folders }
        guard let type = values?.contentType else { return .other }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .pdf) { return .pdfs }
        if type.conforms(to: .audiovisualContent) { return .media }
        if type.conforms(to: .archive) { return .archives }
        if type.conforms(to: .text) || type.conforms(to: .compositeContent)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .presentation) {
            return .documents
        }
        return .other
    }

    // MARK: Arrangement

    private var arrangementKey: String { "arrangement:" + url.path }

    /// File names in the order the user left them.
    private var arrangement: [String] {
        UserDefaults.standard.stringArray(forKey: arrangementKey) ?? []
    }

    func arrange(_ order: [URL]) {
        UserDefaults.standard.set(order.map(\.lastPathComponent), forKey: arrangementKey)
        reload()
    }

    // MARK: Actions

    func open(_ urls: some Sequence<URL>) {
        urls.forEach { url in
            if Finder.isFolder(url) {
                Finder.openFolder(url)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func trash(_ urls: some Collection<URL>) {
        NSWorkspace.shared.recycle(Array(urls))
    }

    /// Zip the items into one archive beside them.
    func compress(_ urls: some Collection<URL>) {
        guard !urls.isEmpty else { return }
        let archive = free(name: "Archive", extension: "zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-q", archive.lastPathComponent] + urls.map(\.lastPathComponent)
        process.currentDirectoryURL = url
        try? process.run()
    }

    /// Give an item a new name. Nil when the name is empty, taken or the same.
    @discardableResult
    func rename(_ item: URL, to name: String) -> URL? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), name != item.lastPathComponent else { return nil }
        let target = url.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: target.path),
              (try? FileManager.default.moveItem(at: item, to: target)) != nil
        else { return nil }
        return target
    }

    @discardableResult
    func newFolder() -> URL? {
        let target = free(name: "untitled folder", extension: "")
        guard (try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)) != nil
        else { return nil }
        return target
    }

    /// Bring items into this folder, moving them or leaving the originals.
    func take(_ items: [URL], copying: Bool) {
        Self.bring(items, into: url, copying: copying)
    }

    /// Bring items into a folder. A name already there gets "copy" after it
    /// rather than being replaced.
    static func bring(_ items: [URL], into folder: URL, copying: Bool) {
        let files = FileManager.default
        for item in items {
            let isThere = item.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
            // Nothing moves into itself or to where it already is.
            if item.standardizedFileURL == folder.standardizedFileURL || (isThere && !copying) { continue }
            var target = folder.appendingPathComponent(item.lastPathComponent)
            if files.fileExists(atPath: target.path) {
                target = free(
                    name: item.deletingPathExtension().lastPathComponent + " copy",
                    extension: item.pathExtension,
                    in: folder
                )
            }
            if copying {
                try? files.copyItem(at: item, to: target)
            } else {
                try? files.moveItem(at: item, to: target)
            }
        }
    }

    func copyToPasteboard(_ items: some Collection<URL>) {
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects(items.map { $0 as NSURL })
    }

    /// Copy in whatever files the pasteboard holds.
    func paste() {
        let found = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        take(found, copying: true)
    }

    /// Move the items into a new folder beside them.
    func group(_ urls: some Collection<URL>) {
        guard !urls.isEmpty else { return }
        let target = free(name: "New Folder", extension: "")
        let files = FileManager.default
        guard (try? files.createDirectory(at: target, withIntermediateDirectories: false)) != nil else { return }
        for item in urls {
            try? files.moveItem(at: item, to: target.appendingPathComponent(item.lastPathComponent))
        }
    }

    /// "Archive.zip", then "Archive 2.zip": the first name nothing has yet.
    private func free(name: String, extension ext: String) -> URL {
        Self.free(name: name, extension: ext, in: url)
    }

    private static func free(name: String, extension ext: String, in folder: URL) -> URL {
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return candidate
    }
}
