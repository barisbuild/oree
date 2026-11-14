import AppKit
import Observation
import SwiftUI

/// A pomodoro: 25 minutes of focus, 5 of rest, round and round.
@Observable
final class FocusTimer {
    enum Phase {
        case focus, rest
        var length: TimeInterval { self == .focus ? 25 * 60 : 5 * 60 }
        var label: String { self == .focus ? "Focus" : "Break" }
    }

    private(set) var phase = Phase.focus
    private(set) var remaining = Phase.focus.length
    private(set) var running = false
    @ObservationIgnored private var ends: Date?
    @ObservationIgnored private var ticker: Timer?

    /// How much of the phase is behind, 0 to 1.
    var progress: Double { 1 - remaining / phase.length }

    func toggle() {
        running ? pause() : start()
    }

    func reset() {
        pause()
        phase = .focus
        remaining = phase.length
    }

    private func start() {
        running = true
        ends = Date().addingTimeInterval(remaining)
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func pause() {
        running = false
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let ends else { return }
        remaining = max(0, ends.timeIntervalSinceNow)
        guard remaining == 0 else { return }
        // Time is up: say so, and stand ready for the other phase.
        NSSound(named: "Glass")?.play()
        pause()
        phase = phase == .focus ? .rest : .focus
        remaining = phase.length
    }
}

/// The time, a line that fills, and one button.
struct FocusWidget: View {
    let timer: FocusTimer

    var body: some View {
        Widget(title: timer.phase.label, icon: .timer, count: nil, height: widgetHeight) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .center) {
                    Text(clock)
                        .font(.system(size: 52, weight: .light))
                        .monospacedDigit()
                    Spacer()
                    Button(action: timer.toggle) {
                        IconView(timer.running ? .pause : .play, size: 18)
                            .frame(width: 44, height: 44)
                            .background(Theme.panel, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(timer.running ? "Pause" : "Start")
                }
                Spacer(minLength: 0)
                GeometryReader { bar in
                    Capsule()
                        .fill(Theme.panel)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Theme.primary)
                                .frame(width: bar.size.width * timer.progress)
                                .animation(.linear(duration: 0.5), value: timer.progress)
                        }
                }
                .frame(height: 3)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Start over", action: timer.reset)
            }
        }
    }

    private var clock: String {
        let seconds = Int(timer.remaining.rounded(.up))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
