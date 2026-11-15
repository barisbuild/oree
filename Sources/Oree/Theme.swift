import AppKit
import SwiftUI

enum Theme {
    /// The ground every screen rests on, and the colour the hero sinks into.
    static func groundRGB(dark: Bool) -> SIMD3<Float> {
        dark ? SIMD3(0.075, 0.075, 0.08) : SIMD3(0.953, 0.953, 0.961)
    }
    static let ground = adaptive(light: NSColor(red: 0.953, green: 0.953, blue: 0.961, alpha: 1),
                                 dark: NSColor(red: 0.075, green: 0.075, blue: 0.08, alpha: 1))
    static let card = adaptive(light: .white, dark: NSColor(red: 0.115, green: 0.115, blue: 0.125, alpha: 1))
    /// What things are drawn in: near black by day, near white by night.
    /// Tints of it make the panels, hairlines and quieter text.
    static let ink = adaptive(light: NSColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1), dark: .white)
    static let panel = ink.opacity(0.07)
    /// A fine dark edge round each card in light mode, where pale glass on a
    /// pale ground would otherwise lose its outline; none in dark mode.
    static let cardEdge = adaptive(light: NSColor.black.withAlphaComponent(0.16), dark: .clear)
    static let hairline = ink.opacity(0.1)
    static let primary = ink.opacity(0.92)
    static let secondary = ink.opacity(0.55)
    static let accent = adaptive(light: NSColor(red: 0.18, green: 0.23, blue: 0.85, alpha: 1),
                                 dark: NSColor(red: 0.36, green: 0.56, blue: 1.0, alpha: 1))

    /// A colour that follows the system's appearance.
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/// Liquid Glass where the system has it, a frosted material where it does not.
private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Theme.hairline))
        }
    }
}

/// Glass with a colour through it, for a control that is ready to use;
/// without a colour it is plain glass. Before macOS 26, a flat fill.
private struct TintedGlass<S: Shape>: ViewModifier {
    let tint: Color?
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(tint.map { .regular.tint($0).interactive() } ?? .regular, in: shape)
        } else if let tint {
            content.background(tint, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Theme.hairline))
        }
    }
}

/// Glass casts a shadow of its own whenever the window is the active one,
/// which on the flat desktop reads as a grey smudge round every card. The
/// glass is drawn as a layer behind the card's content and cut to the
/// card's shape, which leaves the shadow outside it with nowhere to fall.
private struct GlassCard: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    Color.clear
                        .glassEffect(.regular, in: shape)
                        .clipShape(shape)
                }
                .overlay(shape.strokeBorder(Theme.cardEdge))
        } else {
            content
                .background(Theme.card, in: shape)
                .overlay(shape.strokeBorder(Theme.hairline))
        }
    }
}

extension View {
    func glass(in shape: some Shape) -> some View {
        modifier(GlassSurface(shape: shape))
    }

    func glass(tinted tint: Color?, in shape: some Shape) -> some View {
        modifier(TintedGlass(tint: tint, shape: shape))
    }

    /// The card every widget sits on: Liquid Glass where the system has it.
    func card() -> some View {
        modifier(GlassCard())
    }
}

/// Glass shapes that touch inside a group flow into one another.
struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) { content }
        } else {
            content
        }
    }
}
