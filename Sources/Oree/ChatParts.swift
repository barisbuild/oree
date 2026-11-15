import SwiftUI

// The pieces a conversation is drawn with while an agent works: the
// status above the reply box, the trace of the tools it ran, and its
// answers arriving a word at a time.

/// A label with a band of light passing across it, for something under way.
struct ShimmerText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var still

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if still {
            Text(text).foregroundStyle(Theme.secondary)
        } else {
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                Text(text)
                    .foregroundStyle(Theme.secondary.opacity(0.7))
                    .overlay {
                        Text(text)
                            .foregroundStyle(Theme.primary)
                            .mask {
                                GeometryReader { box in
                                    LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: box.size.width * 0.6)
                                        .offset(x: (phase * 1.6 - 0.6) * box.size.width)
                                }
                            }
                    }
            }
        }
    }
}

/// A small square of dots with a lit band sweeping corner to corner.
private struct DotWave: View {
    let time: Double?

    var body: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 1)
                            .frame(width: 4, height: 4)
                            .opacity(brightness(row: row, column: column))
                    }
                }
            }
        }
    }

    /// Each dot lights as the band reaches its diagonal and dims behind it.
    private func brightness(row: Int, column: Int) -> Double {
        guard let time else { return 0.2 + 0.2 * Double(row + column) }
        let band = (time / 0.7).truncatingRemainder(dividingBy: 1) * 1.4 - 0.2
        let distance = abs(Double(row + column) / 4 - band)
        return 0.15 + 0.85 * max(0, 1 - distance / 0.35)
    }
}

/// The agent is working: a moving mark, what it is doing, and for how long.
struct ThinkingIndicator: View {
    let label: String
    @State private var started = Date()
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        TimelineView(.periodic(from: .now, by: still ? 0.1 : 1.0 / 30)) { context in
            let elapsed = context.date.timeIntervalSince(started)
            HStack(spacing: 10) {
                DotWave(time: still ? nil : elapsed)
                    .foregroundStyle(Theme.secondary)
                ShimmerText(label)
                    .font(.callout.weight(.medium))
                Text(String(format: "%.1fs", elapsed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondary.opacity(0.8))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// The tools an agent ran between two things it said, folded into one
/// line. It stays open while they run and closes once the agent speaks
/// again; a click opens or closes it either way.
struct ToolTrace: View {
    let tools: [AgentSession.Entry]
    let running: Bool
    @State private var opened: Bool?

    var body: some View {
        let expanded = opened ?? running
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.smooth(duration: 0.3)) { opened = !expanded }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(running ? Theme.primary : Theme.secondary)
                    if running {
                        ShimmerText("Running tools")
                    } else {
                        Text(summary).foregroundStyle(Theme.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .font(.callout.weight(.medium))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tools) { entry in
                        Text(entry.text)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                }
                .padding(.leading, 16)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1)
                        .padding(.leading, 5)
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: tools.count)
        .animation(.smooth(duration: 0.3), value: running)
    }

    /// "Ran 3 tools": the answers to its requests are not counted again.
    private var summary: String {
        let ran = tools.filter { !$0.text.hasPrefix("Allowed ·") && !$0.text.hasPrefix("Denied ·") }.count
        return ran == 1 ? "Ran 1 tool" : "Ran \(ran) tools"
    }
}

/// An answer that arrives a word at a time, each word fading in. Words not
/// yet shown keep their place, so the text never reflows as it fills.
/// Older answers, and any shown again later, appear whole.
struct StreamingText: View {
    let text: AttributedString
    let since: Date
    @Environment(\.accessibilityReduceMotion) private var still

    /// Seconds per word: brisk, and never more than about a second and a
    /// half for the whole answer.
    private var step: Double {
        min(0.035, 1.5 / Double(max(1, wordCount)))
    }

    private var wordCount: Int {
        String(text.characters).split(whereSeparator: \.isWhitespace).count
    }

    private var duration: Double { step * Double(wordCount + 3) }

    var body: some View {
        if still || Date().timeIntervalSince(since) > duration {
            Text(text)
        } else {
            TimelineView(.animation) { context in
                Text(Self.reveal(text, shown: context.date.timeIntervalSince(since) / step))
            }
        }
    }

    /// The text with words past `shown` hidden, and the last three fading in.
    private static func reveal(_ base: AttributedString, shown: Double) -> AttributedString {
        var out = base
        var starts: [AttributedString.Index] = []
        var afterSpace = true
        var index = out.startIndex
        while index < out.endIndex {
            let space = out.characters[index].isWhitespace
            if !space && afterSpace { starts.append(index) }
            afterSpace = space
            index = out.characters.index(after: index)
        }
        for (number, start) in starts.enumerated() where Double(number) > shown - 3 {
            let end = number + 1 < starts.count ? starts[number + 1] : out.endIndex
            let opacity = min(1, max(0, (shown - Double(number)) / 3))
            out[start..<end].foregroundColor = Theme.primary.opacity(opacity)
        }
        return out
    }
}
