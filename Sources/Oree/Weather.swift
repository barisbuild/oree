import CoreLocation
import Observation
import SwiftUI

/// The weather where the Mac is, from Open-Meteo. The position sent is
/// rounded to about a kilometre, and nothing else goes with it.
@Observable
final class WeatherFeed: NSObject, CLLocationManagerDelegate {
    struct Day: Identifiable {
        let id: Int
        let name: String
        let icon: Icon
        let high: Int
        let low: Int
    }

    enum State { case locating, denied, failed, ready }

    private(set) var state = State.locating
    private(set) var place = ""
    private(set) var temperature = 0
    private(set) var summary = ""
    private(set) var icon = Icon.cloud
    private(set) var days: [Day] = []
    @ObservationIgnored private let locator = CLLocationManager()
    @ObservationIgnored private var lastRead = Date.distantPast

    override init() {
        super.init()
        locator.delegate = self
        locator.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Weather moves slowly: read it at most every half hour.
    func refresh() {
        if Demo.on {
            place = "Lisbon"
            temperature = 18
            summary = "Partly cloudy"
            icon = .sunCloud
            days = [("Today", Icon.sunCloud, 20, 14), ("Sun", .sun, 23, 15), ("Mon", .rain, 19, 13), ("Tue", .cloud, 18, 12)]
                .enumerated().map { Day(id: $0.offset, name: $0.element.0, icon: $0.element.1, high: $0.element.2, low: $0.element.3) }
            state = .ready
            return
        }
        guard Date().timeIntervalSince(lastRead) > 30 * 60 else { return }
        switch locator.authorizationStatus {
        case .notDetermined: locator.requestWhenInUseAuthorization()
        case .denied, .restricted: state = .denied
        default: locator.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refresh()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if state != .ready { state = .failed }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastRead = Date()
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] found, _ in
            if let name = found?.first?.locality { self?.place = name }
        }
        Task { await read(at: location.coordinate) }
    }

    private func read(at position: CLLocationCoordinate2D) async {
        let address = String(
            format: "https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f"
                + "&current=temperature_2m,weather_code,is_day"
                + "&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=4",
            position.latitude, position.longitude
        )
        guard let url = URL(string: address),
              let (data, _) = try? await URLSession.oree.data(from: url),
              let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = reply["current"] as? [String: Any],
              let daily = reply["daily"] as? [String: Any],
              let now = current["temperature_2m"] as? Double,
              let code = current["weather_code"] as? Int,
              let codes = daily["weather_code"] as? [Int],
              let highs = daily["temperature_2m_max"] as? [Double],
              let lows = daily["temperature_2m_min"] as? [Double],
              let dates = daily["time"] as? [String]
        else {
            await MainActor.run {
                // Try again at the next refresh rather than in half an hour.
                self.lastRead = .distantPast
                if self.state != .ready { self.state = .failed }
            }
            return
        }
        let isDay = (current["is_day"] as? Int ?? 1) == 1
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        let days = (0..<min(codes.count, highs.count, lows.count, dates.count)).map { index in
            Day(
                id: index,
                name: index == 0 ? "Today" : parser.date(from: dates[index])?
                    .formatted(.dateTime.weekday(.abbreviated)) ?? "",
                icon: Self.look(of: codes[index], isDay: true).icon,
                high: Int(highs[index].rounded()),
                low: Int(lows[index].rounded())
            )
        }
        await MainActor.run {
            self.temperature = Int(now.rounded())
            (self.summary, self.icon) = Self.look(of: code, isDay: isDay)
            self.days = days
            self.state = .ready
        }
    }

    /// The words and the icon for a WMO weather code.
    private static func look(of code: Int, isDay: Bool) -> (summary: String, icon: Icon) {
        switch code {
        case 0: ("Clear", isDay ? .sun : .moon)
        case 1, 2: ("Partly cloudy", isDay ? .sunCloud : .cloud)
        case 3: ("Overcast", .cloud)
        case 45, 48: ("Fog", .wind)
        case 51...57: ("Drizzle", .rain)
        case 61...67, 80...82: ("Rain", .rain)
        case 71...77, 85, 86: ("Snow", .snow)
        case 95...99: ("Thunderstorm", .storm)
        default: ("Cloudy", .cloud)
        }
    }
}

struct WeatherWidget: View {
    let feed: WeatherFeed

    var body: some View {
        Widget(title: "Weather", icon: .sunCloud, count: nil, height: widgetHeight) {
            switch feed.state {
            case .locating:
                Hint("Finding where you are…")
            case .denied:
                Hint("Allow Oree to use your location in System Settings, under Privacy & Security, Location Services.")
            case .failed:
                Hint("The weather could not be read. It is tried again every minute.")
            case .ready:
                VStack(alignment: .leading, spacing: 0) {
                    // Two columns from the same top line: where and how warm
                    // on the left; the sky, what it is doing and the day's
                    // range on the right.
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(feed.place.isEmpty ? "Here" : feed.place)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text("\(feed.temperature)°")
                                .font(.system(size: 42, weight: .light))
                                .monospacedDigit()
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            IconView(feed.icon, size: 22)
                            Text(feed.summary)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            if let today = feed.days.first {
                                Text("H \(today.high)°  L \(today.low)°")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    Spacer(minLength: 10)
                    // The days ahead, on a panel of their own.
                    HStack(spacing: 0) {
                        ForEach(feed.days) { day in
                            VStack(spacing: 5) {
                                Text(day.name)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                                IconView(day.icon, size: 17)
                                HStack(spacing: 4) {
                                    Text("\(day.high)°").fontWeight(.medium)
                                    Text("\(day.low)°").foregroundStyle(Theme.secondary)
                                }
                                .font(.caption)
                                .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Theme.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}
