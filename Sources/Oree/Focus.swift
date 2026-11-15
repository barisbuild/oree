import AppKit
import Observation
import SwiftUI

/// A pomodoro: focus for as long as the user has set (25 minutes unless
/// changed), then 5 minutes of rest, round and round.
@Observable
final class FocusTimer {
    enum Phase {
        case focus, rest
        var label: String { self == .focus ? "Focus" : "Break" }
    }

    /// How long a focus runs, in minutes; kept across launches.
    private(set) var focusMinutes: Int
    private(set) var phase = Phase.focus
    private(set) var remaining: TimeInterval
    private(set) var running = false
    @ObservationIgnored private var ends: Date?
    @ObservationIgnored private var ticker: Timer?

    init() {
        let saved = UserDefaults.standard.integer(forKey: "focusMinutes")
        let minutes = (1...60).contains(saved) ? saved : 25
        focusMinutes = minutes
        remaining = TimeInterval(minutes * 60)
    }

    func length(of phase: Phase) -> TimeInterval {
        phase == .focus ? TimeInterval(focusMinutes * 60) : 5 * 60
    }

    /// How much of the phase is behind, 0 to 1.
    var progress: Double { 1 - remaining / length(of: phase) }

    /// A focus not yet begun: the only time its length may be changed.
    var isFresh: Bool { !running && phase == .focus && remaining == length(of: .focus) }

    /// Set how long a focus runs, while none is under way.
    func set(minutes: Int) {
        guard isFresh else { return }
        focusMinutes = min(60, max(1, minutes))
        remaining = length(of: .focus)
        UserDefaults.standard.set(focusMinutes, forKey: "focusMinutes")
    }

    func toggle() {
        running ? pause() : start()
    }

    func reset() {
        pause()
        phase = .focus
        remaining = length(of: phase)
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
        remaining = length(of: phase)
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
                    if !timer.isFresh {
                        Button(action: timer.reset) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(Theme.panel, in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Start over")
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
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
                Ruler(remaining: timer.remaining / 60, adjustable: timer.isFresh, set: timer.set(minutes:))
            }
            .frame(maxHeight: .infinity)
            .animation(.smooth(duration: 0.25), value: timer.isFresh)
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

/// A kitchen timer's scale laid flat: an hour, a tick for every minute and
/// a longer one with its number every five, sliding under a fixed needle
/// that points at the minutes left. Past the needle the scale is dimmed.
/// Before a focus begins it can be dragged to set how long it runs, a
/// minute at a time, with a tick felt on the trackpad at each.
private struct Ruler: View {
    let remaining: Double
    let adjustable: Bool
    let set: (Int) -> Void
    /// Where a drag began, in minutes.
    @State private var dragStart: Double?

    private static let spacing: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            let middle = size.width / 2
            for minute in 0...60 {
                let x = middle + (CGFloat(minute) - remaining) * Self.spacing
                guard x > -12, x < size.width + 12 else { continue }
                let major = minute % 5 == 0
                let past = Double(minute) > remaining
                let tick = Path(CGRect(x: x - 0.5, y: 8, width: 1, height: major ? 13 : 7))
                context.fill(tick, with: .color(Theme.secondary.opacity(past ? 0.35 : 1)))
                if major {
                    context.draw(
                        Text("\(minute)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.secondary.opacity(past ? 0.35 : 1)),
                        at: CGPoint(x: x, y: 31)
                    )
                }
            }
        }
        // The scale fades out at both ends rather than stopping short.
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                        .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .top) {
            Capsule()
                .fill(Theme.accent)
                .frame(width: 2.5, height: 24)
        }
        .frame(height: 38)
        // Edge to edge across the card, past its padding.
        .padding(.horizontal, -14)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { drag in
                    guard adjustable else { return }
                    let start = dragStart ?? remaining
                    dragStart = start
                    // The scale follows the hand: drawn right, fewer minutes.
                    let minutes = Int((start - drag.translation.width / Self.spacing).rounded())
                    if minutes != Int(remaining.rounded()), (1...60).contains(minutes) {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        set(minutes)
                    }
                }
                .onEnded { _ in dragStart = nil }
        )
        .onHover { inside in
            if inside && adjustable { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .help(adjustable ? "Drag to set how long a focus runs" : "")
        .accessibilityHidden(true)
    }
}
