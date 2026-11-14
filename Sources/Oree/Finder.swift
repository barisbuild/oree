import AppKit

enum Finder {
    static let app = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)
    static let revealClass: AEEventClass = 0x6D697363 // misc
    static let revealEvent: AEEventID = 0x6D766973 // mvis
    private static let bundle = "com.apple.finder"

    static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    static func openFolder(_ url: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        // The system's file viewer points to Oree. Address Finder directly
        // to avoid sending the reveal request back to this process.
        DispatchQueue.global(qos: .userInitiated).async {
            let event = NSAppleEventDescriptor(
                eventClass: revealClass,
                eventID: revealEvent,
                targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundle),
                returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            )
            let items = NSAppleEventDescriptor.list()
            for (index, url) in urls.enumerated() {
                items.insert(NSAppleEventDescriptor(fileURL: url), at: index + 1)
            }
            event.setParam(items, forKeyword: keyDirectObject)
            let reply = try? event.sendEvent(options: .waitForReply, timeout: 10)
            let error = reply?.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0
            DispatchQueue.main.async {
                if reply != nil, error == 0 {
                    NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.activate()
                } else {
                    // Finder can still open the containing folders if macOS
                    // denies permission to select the files via Apple events.
                    Set(urls.map { $0.deletingLastPathComponent() }).forEach(openFolder)
                }
            }
        }
    }
}
