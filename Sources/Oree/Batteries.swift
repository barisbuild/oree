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

    /// Every device with a battery: the ones that report a level first.
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
            let accessories = Self.accessories()
            let named = Set(accessories.map { $0.name.lowercased() })
            // The Bluetooth report fills in what the power sources leave out,
            // such as devices that are away but left a level behind.
            let all = Self.thisMac() + accessories + Self.bluetooth().filter { !named.contains($0.name.lowercased()) }
            let known = all.filter { $0.level != nil }
            // Of the silent ones, a keyboard or a mouse is the likelier wish.
            let silent = all.filter { $0.level == nil && !$0.stale }
                .sorted { Self.rank($0.icon) < Self.rank($1.icon) }
            await MainActor.run { self.devices = known + silent }
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
                charging: about[kIOPSIsChargingKey] as? Bool == true,
                stale: false
            )
        }
    }

    /// The accessories the system tracks the power of: the same list its own
    /// Batteries widget reads, with AirPods Max, keyboards and mice that the
    /// Bluetooth report gives no level for.
    private static func accessories() -> [Device] {
        typealias ByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOPSCopyPowerSourcesByType"),
              let info = unsafeBitCast(symbol, to: ByType.self)(0)?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }
        return sources.compactMap { source in
            guard let about = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  about[kIOPSTypeKey] as? String != kIOPSInternalBatteryType,
                  let name = about[kIOPSNameKey] as? String
            else { return nil }
            // A pair of earbuds comes as parts: as charged as the emptier one.
            let parts = about["Combined Parts"] as? [[String: Any]] ?? []
            let levels = (parts.isEmpty ? [about] : parts).compactMap { $0[kIOPSCurrentCapacityKey] as? Int }
            guard let level = levels.min() else { return nil }
            let charging = (parts.isEmpty ? [about] : parts).contains { $0[kIOPSIsChargingKey] as? Bool == true }
            let category = (about["Accessory Category"] as? String ?? "").lowercased()
            let icon: Icon = category.contains("case") ? .earbudsCase
                : category.contains("headset") || category.contains("headphone")
                    ? (parts.isEmpty && about["Part Identifier"] as? String == "Single" ? .headphones : .earbuds)
                : category.contains("keyboard") ? .keyboard
                : category.contains("mouse") || category.contains("trackpad") ? .mouse
                : category.contains("phone") ? .phone
                : .bluetooth
            let id = about["Accessory Identifier"] as? String ?? name
            return Device(id: id, name: name, icon: icon, level: level, charging: charging, stale: false)
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
    /// Which four are showing, when there are more than four.
    @State private var page = 0

    private var pages: Int { max(1, (feed.devices.count + 3) / 4) }
    private var shown: [BatteryFeed.Device] { Array(feed.devices.dropFirst(min(page, pages - 1) * 4).prefix(4)) }

    var body: some View {
        Widget(
            title: "Batteries", icon: .battery, count: nil, height: widgetHeight,
            link: pages > 1 ? "Next →" : nil,
            follow: { withAnimation(.smooth(duration: 0.3)) { page = (min(page, pages - 1) + 1) % pages } }
        ) {
            Grid(horizontalSpacing: 28, verticalSpacing: 14) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            Ring(device: index < shown.count ? shown[index] : nil)
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

    /// The share of the ring left open at the top for the bolt.
    private var gap: CGFloat { charging ? 0.05 : 0 }

    private var colour: Color {
        guard let level = device?.level else { return .clear }
        return level <= 10 ? .red : level <= 20 ? .orange : .green
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: gap, to: 1 - gap)
                .stroke(Theme.panel, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let device {
                Circle()
                    .trim(from: gap, to: gap + (1 - 2 * gap) * CGFloat(device.level ?? 0) / 100)
                    .stroke(colour, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                IconView(device.icon, size: 26)
                    .opacity(device.level == nil ? 0.45 : 1)
                // Charging, as the system's own widget shows it: a small
                // bolt in a gap at the top of the ring.
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(colour)
                        .offset(y: -31)
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
