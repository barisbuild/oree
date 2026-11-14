import SwiftUI

/// Every widget on the desktop is this tall, so the rows line up.
let widgetHeight: CGFloat = 212

/// The desktop's widgets.
struct WidgetGrid: View {
    let store: SessionStore
    let showFolders: () -> Void
    let showFolder: (URL) -> Void

    private static let gap: CGFloat = 12

    var body: some View {
        GeometryReader { area in
            let columns = columns(in: area.size)
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Self.gap),
                        count: columns
                    ),
                    spacing: Self.gap
                ) {
                    FilesWidget(store: store, showFolders: showFolders, showFolder: showFolder)
                    CalendarWidget(feed: store.calendar)
                    RemindersWidget(feed: store.reminders)
                    MailWidget(feed: store.mail)
                    NowPlayingWidget(playing: store.playing)
                    WeatherWidget(feed: store.weather)
                    BatteryWidget(feed: store.batteries)
                    FocusWidget(timer: store.focus)
                }
            }
            // When every widget fits, the grid is not a thing that scrolls:
            // a wheel over it moves nothing.
            .scrollDisabled(fits(columns, in: area.size))
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
        }
    }

    /// How many widgets there are.
    private let count = 8

    private func fits(_ columns: Int, in size: CGSize) -> Bool {
        let rows = CGFloat((count + columns - 1) / columns)
        return rows * widgetHeight + (rows - 1) * Self.gap <= size.height
    }

    /// As few columns as let every widget fit without scrolling; when even
    /// the most the width allows cannot, that many, and the grid scrolls.
    private func columns(in size: CGSize) -> Int {
        let most = max(1, Int((size.width + Self.gap) / (260 + Self.gap)))
        for columns in min(3, most)...most {
            if fits(columns, in: size) { return columns }
        }
        return most
    }
}

/// The folders in one widget. A row opens that folder; the link opens all.
private struct FilesWidget: View {
    let store: SessionStore
    let showFolders: () -> Void
    let showFolder: (URL) -> Void

    var body: some View {
        Widget(title: "Files", icon: .folder, count: nil, height: widgetHeight, link: "Show all folders", follow: showFolders) {
            if store.roots.isEmpty {
                Hint("Pin a folder in Settings to see it here.")
            } else {
                VStack(spacing: 2) {
                    ForEach(store.roots.prefix(5), id: \.self) { root in
                        let folder = store.folder(root)
                        Button {
                            showFolder(root)
                        } label: {
                            HStack(spacing: 8) {
                                FileIcon(url: root, size: 18)
                                Text(folder.name)
                                Spacer()
                                Text("\(folder.items.count)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
