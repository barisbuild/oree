import Foundation
import IOKit.ps
import Observation
import AppKit
import SwiftUI

/// The charge of this Mac and of the Bluetooth devices around it:
/// headphones and their case, keyboards, mice, trackpads.
@Observable
final class BatteryFeed {
    struct Device: Identifiable {
        let id: String
        let name: String
        let icon: Icon
        /// 0 to 100; nil for a device that is connected but does not say.
        let level: Int?
        let charging: Bool
        /// Not connected now; the level is the last one it reported.
        let stale: Bool
    }

    /// Four at most: the ones that report a level first.
    private(set) var devices: [Device] = []

    func refresh() {
        if Demo.on {
            devices = [
                Device(id: "mac", name: "This Mac", icon: .laptop, level: 71, charging: true, stale: false),
                Device(id: "buds", name: "AirPods", icon: .earbuds, level: 92, charging: false, stale: false),
                Device(id: "case", name: "Case", icon: .earbudsCase, level: 64, charging: false, stale: false),
                Device(id: "keys", name: "Keyboard", icon: .keyboard, level: 38, charging: false, stale: false),
            ]
            return
        }
        Task.detached(priority: .utility) {
            let all = Self.thisMac() + Self.bluetooth()
            let known = all.filter { $0.level != nil }
            // Of the silent ones, a keyboard or a mouse is the likelier wish.
            let silent = all.filter { $0.level == nil && !$0.stale }
                .sorted { Self.rank($0.icon) < Self.rank($1.icon) }
            await MainActor.run { self.devices = Array((known + silent).prefix(4)) }
        }
    }

    private static func rank(_ icon: Icon) -> Int {
        switch icon {
        case .keyboard: 0
        case .mouse: 1
        default: 2
        }
    }

    private static func thisMac() -> [Device] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }
        return sources.compactMap { source in
            guard let about = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  about[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let level = about[kIOPSCurrentCapacityKey] as? Int
            else { return nil }
            return Device(
                id: "mac",
                name: Host.current().localizedName ?? "This Mac",
                icon: .laptop,
                level: level,
                charging: about[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                stale: false
            )
        }
    }

    /// The system's own Bluetooth report: connected devices first, then the
    /// ones that are away but left a level behind.
    private static func bluetooth() -> [Device] {
        guard let output = Shell.output("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]),
              let report = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
              let section = (report["SPBluetoothDataType"] as? [[String: Any]])?.first
        else { return [] }

        func devices(under key: String, stale: Bool) -> [Device] {
            (section[key] as? [[String: Any]] ?? []).flatMap { entry in
                entry.sorted { $0.key < $1.key }.flatMap { name, value -> [Device] in
                    guard let about = value as? [String: Any] else { return [] }
                    func level(_ key: String) -> Int? {
                        (about[key] as? String).flatMap { Int($0.filter(\.isNumber)) }
                    }
                    let address = about["device_address"] as? String ?? name
                    let kind = (about["device_minorType"] as? String ?? "").lowercased()
                    let icon: Icon = kind.contains("head") ? .headphones
                        : kind.contains("keyboard") ? .keyboard
                        : kind.contains("mouse") || kind.contains("trackpad") ? .mouse
                        : kind.contains("phone") ? .phone
                        : .bluetooth
                    let buds = [level("device_batteryLevelLeft"), level("device_batteryLevelRight")].compactMap { $0 }
                    var found: [Device] = []
                    if let charge = buds.min() {
                        // Earbuds are as charged as the emptier one.
                        found.append(Device(id: address, name: name, icon: .earbuds, level: charge, charging: false, stale: stale))
                    } else if let charge = level("device_batteryLevelMain") {
                        found.append(Device(id: address, name: name, icon: icon, level: charge, charging: false, stale: stale))
                    } else if !stale {
                        found.append(Device(id: address, name: name, icon: icon, level: nil, charging: false, stale: false))
                    }
                    // Their case is a battery of its own.
                    if let charge = level("device_batteryLevelCase") {
                        found.append(Device(id: address + "-case", name: "\(name) case", icon: .earbudsCase, level: charge, charging: false, stale: stale))
                    }
                    return found
                }
            }
        }
        return devices(under: "device_connected", stale: false)
            + devices(under: "device_not_connected", stale: true)
    }
}

/// Four rings, two by two, each closed as far as its device is charged.
/// No words: the icon says which device, the ring says how full.
struct BatteryWidget: View {
    let feed: BatteryFeed

    var body: some View {
        Widget(title: "Batteries", icon: .battery, count: nil, height: widgetHeight) {
            Grid(horizontalSpacing: 28, verticalSpacing: 14) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            Ring(device: index < feed.devices.count ? feed.devices[index] : nil)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct Ring: View {
    /// Nil draws an empty place, so the four always hold their shape.
    let device: BatteryFeed.Device?


    private var charging: Bool { device?.charging == true }

    private var colour: Color {
        guard let level = device?.level else { return .clear }
        return level <= 10 ? .red : level <= 20 ? .orange : .green
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.panel, lineWidth: 5)
            if let device {
                Circle()
                    .trim(from: 0, to: CGFloat(device.level ?? 0) / 100)
                    .stroke(colour, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if charging {
                    // Charging: the device gives way to a green bolt in the
                    // middle of the ring, then comes back.
                    IconSwap(first: device.icon, second: .bolt, secondColour: NSColor(colour))
                        .frame(width: 24, height: 24)
                } else {
                    IconView(device.icon, size: 26)
                        .opacity(device.level == nil ? 0.45 : 1)
                }
            }
        }
        .frame(width: 62, height: 62)
        .opacity(device?.stale == true ? 0.55 : 1)
        .help(device.map { device in
            device.level.map { "\(device.name): \($0)%" } ?? "\(device.name): no level reported"
        } ?? "")
    }
}

/// Two icons in one place, each fading into the other in turn. The system's
/// compositor runs the animation, so it costs the app nothing while it plays.
private struct IconSwap: NSViewRepresentable {
    let first: Icon
    let second: Icon
    let secondColour: NSColor

    func makeNSView(context: Context) -> IconSwapView {
        IconSwapView(first: first, second: second, secondColour: secondColour)
    }

    func updateNSView(_ view: IconSwapView, context: Context) {}
}

private final class IconSwapView: NSView {
    private let first = CALayer()
    private let second = CALayer()

    init(first: Icon, second: Icon, secondColour: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        Self.paint(self.first, with: first, colour: NSColor(Theme.primary))
        Self.paint(self.second, with: second, colour: secondColour)
        self.second.opacity = 0
        layer?.addSublayer(self.first)
        layer?.addSublayer(self.second)
    }

    required init?(coder: NSCoder) { nil }

    /// A layer of one colour, cut to the icon's shape.
    private static func paint(_ layer: CALayer, with icon: Icon, colour: NSColor) {
        let shape = CALayer()
        shape.contents = icon.symbolImage(pointSize: 44)
        shape.contentsGravity = .resizeAspect
        layer.backgroundColor = colour.cgColor
        layer.mask = shape
    }

    override func layout() {
        super.layout()
        for layer in [first, second] {
            layer.frame = bounds
            layer.mask?.frame = bounds
        }
    }

    // Animations are dropped when a view leaves its window; start again
    // whenever it is put in one.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // Mostly the device; the bolt takes a short turn in each round. One
        // shrinks away as the other grows into its place, so the change
        // reads as one shape becoming the other.
        first.add(Self.turn(opacity: [1, 1, 0, 0, 1], scale: [1, 1, 0.4, 0.4, 1]), forKey: "turn")
        second.add(Self.turn(opacity: [0, 0, 1, 1, 0], scale: [0.4, 0.4, 1, 1, 0.4]), forKey: "turn")
    }

    private static func turn(opacity: [Float], scale: [Float]) -> CAAnimationGroup {
        let times: [NSNumber] = [0, 0.52, 0.64, 0.86, 0.98]
        // Each change eases in and out on its own.
        let easing = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: times.count - 1)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = opacity
        let size = CAKeyframeAnimation(keyPath: "transform.scale")
        size.values = scale
        for part in [fade, size] {
            part.keyTimes = times
            part.timingFunctions = easing
        }
        let turn = CAAnimationGroup()
        turn.animations = [fade, size]
        turn.duration = 7
        turn.repeatCount = .infinity
        return turn
    }
}

