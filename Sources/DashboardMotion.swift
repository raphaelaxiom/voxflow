import SwiftUI
import AppKit

// MARK: - Motion + theme for the Dashboard
//
// Original SwiftUI work. The MOTION LANGUAGE is informed by the free
// web-effect libraries Verse pointed at (OriginKit free effects +
// the 21st.dev hero's entrance), but every implementation below is
// native SwiftUI written for this app — no React, no JS, no copied code,
// no WebGL shaders.
//
// Hard constraints honored here:
// - Total entrance motion stays under ~600ms.
// - Only the banner gradient + floating icons loop, at low opacity.
// - Interaction is never blocked (no hit-testing overlays).
// - macOS Reduce Motion renders every effect instantly in its final state.

/// Central Reduce-Motion gate. All motion views in this file consult it.
enum VoxflowMotion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Delay step for staggered entrances. 40ms × ≤12 items keeps the
    /// whole entrance under ~600ms.
    static let staggerStep: Double = 0.04
}

// MARK: - Theme (21st.dev hero-adapted, Voxflow identity)

extension Color {
    /// Warm ivory paper — the light theme's canvas.
    static let voxflowPaper = Color(red: 0.992, green: 0.988, blue: 0.976)
    /// Warm sand card fill.
    static let voxflowCard = Color(red: 1.0, green: 0.996, blue: 0.992)
    /// Primary accent: amber → coral, matching the Voxflow logo.
    static let voxflowAmber = Color(red: 1.0, green: 0.69, blue: 0.13)
    static let voxflowCoral = Color(red: 1.0, green: 0.35, blue: 0.24)
    static let voxflowInk = Color(red: 0.10, green: 0.09, blue: 0.09)
}

extension LinearGradient {
    /// Hero gradient: pastel wash (white → peach → blush → lilac) with
    /// Voxflow's amber→coral as the accent edge. Light theme.
    static let voxflowHero = LinearGradient(
        colors: [
            Color.white,
            Color(red: 1.0, green: 0.93, blue: 0.84), // #FFEDD5
            Color(red: 1.0, green: 0.85, blue: 0.73), // #FFDAB9
            Color(red: 1.0, green: 0.71, blue: 0.76), // #FFB6C1
            Color(red: 0.88, green: 0.73, blue: 0.89), // #E0BBE4
            Color(red: 0.95, green: 0.90, blue: 0.96), // #F3E5F5
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Dark-theme twin of the hero gradient: same layout, deep plum +
    /// amber-coral glow instead of pastels.
    static let voxflowHeroDark = LinearGradient(
        colors: [
            Color(red: 0.16, green: 0.13, blue: 0.16),
            Color(red: 0.26, green: 0.16, blue: 0.20),
            Color(red: 0.35, green: 0.20, blue: 0.18),
            Color(red: 0.22, green: 0.14, blue: 0.26),
            Color(red: 0.12, green: 0.10, blue: 0.14),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Amber → coral accent used for primary actions and highlights.
    static let voxflowAccent = LinearGradient(
        colors: [.voxflowAmber, .voxflowCoral],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - 1. Stagger text rise (per-letter rise, spring, on load)

/// Per-letter rise with a spring and ~40ms stagger, on appear.
/// Used for the "Welcome back" heading and section headings.
struct StaggeredRiseText: View {
    let text: String
    let font: Font
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(font)
                    .opacity(VoxflowMotion.reduceMotion ? 1 : (appeared ? 1 : 0))
                    .offset(y: VoxflowMotion.reduceMotion ? 0 : (appeared ? 0 : 14))
                    .blur(radius: VoxflowMotion.reduceMotion ? 0 : (appeared ? 0 : 4))
                    .animation(
                        VoxflowMotion.reduceMotion ? nil :
                            .spring(response: 0.35, dampingFraction: 0.82)
                            .delay(min(Double(index) * VoxflowMotion.staggerStep, 0.48)),
                        value: appeared
                    )
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - 2. Text emerge (word-by-word scale + blur + opacity, from center)

/// Word-by-word emerge: scale + blur + opacity, staggered from the center.
/// Used for banner subtitles and empty-state text.
struct EmergeText: View {
    let text: String
    let font: Font
    @State private var appeared = false

    private var words: [String] { text.split(separator: " ").map(String.init) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(font)
                    .opacity(VoxflowMotion.reduceMotion ? 1 : (appeared ? 1 : 0))
                    .scaleEffect(VoxflowMotion.reduceMotion ? 1 : (appeared ? 1 : 0.86))
                    .blur(radius: VoxflowMotion.reduceMotion ? 0 : (appeared ? 0 : 6))
                    .animation(
                        VoxflowMotion.reduceMotion ? nil :
                            .easeOut(duration: 0.3)
                            .delay(min(Double(index) * VoxflowMotion.staggerStep, 0.4)),
                        value: appeared
                    )
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - 3. Text wipe (clip-path wipe reveal, left → right, on appear)

/// Clip-path wipe reveal, left → right, on appear. Used for the banner headline.
struct WipeRevealText: View {
    let text: String
    let font: Font
    let color: Color
    @State private var progress: CGFloat = 0

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .mask(
                GeometryReader { geo in
                    Rectangle()
                        .frame(width: max(0, geo.size.width * (VoxflowMotion.reduceMotion ? 1 : progress)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            )
            .onAppear {
                if VoxflowMotion.reduceMotion {
                    progress = 1
                } else {
                    withAnimation(.easeOut(duration: 0.5)) { progress = 1 }
                }
            }
    }
}

// MARK: - 4. Skew-in (shear slide-in, subtle, on load)

/// Shear transform used for the subtle skew slide-in.
struct SkewEffect: GeometryEffect {
    var skew: CGFloat // horizontal shear factor; ~0.12 is subtle

    var animatableData: CGFloat {
        get { skew }
        set { skew = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(a: 1, b: 0, c: skew, d: 1, tx: 0, ty: 0))
    }
}

/// Skewed slide-in for TODAY headers + stat labels. Subtle by design.
struct SkewInText: View {
    let text: String
    let font: Font
    @State private var appeared = false

    var body: some View {
        Text(text)
            .font(font)
            .modifier(SkewEffect(skew: VoxflowMotion.reduceMotion ? 0 : (appeared ? 0 : 0.14)))
            .offset(x: VoxflowMotion.reduceMotion ? 0 : (appeared ? 0 : -10))
            .opacity(VoxflowMotion.reduceMotion ? 1 : (appeared ? 1 : 0))
            .animation(
                VoxflowMotion.reduceMotion ? nil :
                    .spring(response: 0.35, dampingFraction: 0.9),
                value: appeared
            )
            .onAppear { appeared = true }
    }
}

// MARK: - 5. Filled wordmark (solid letters + thin orange hairline)

/// "VOXFLOW" wordmark: SOLID filled letters with a thin orange outline
/// (negative strokeWidth = fill + stroke), full opacity, no drift.
///
/// The previous version was stroke-ONLY (positive strokeWidth) at 60–90%
/// opacity with a slow opacity drift — on the pastel hero it rendered as
/// a faint ghost outline. v0.1.4 makes it crisp and properly visible:
/// filled ink/white letters, hairline brand-orange edge, static.
struct OutlinedWordmarkView: View {
    let text: String
    let fontSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        OutlinedTextRepresentable(
            text: text,
            fontSize: fontSize,
            fillColor: colorScheme == .dark ? .white : NSColor(red: 0.10, green: 0.09, blue: 0.09, alpha: 1.0)
        )
    }
}

private struct OutlinedTextRepresentable: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let fillColor: NSColor

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = false
        field.drawsBackground = false
        field.alignment = .center
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fillColor,
            .strokeColor: NSColor(red: 1.0, green: 0.55, blue: 0.25, alpha: 1.0),
            .strokeWidth: -1.2, // negative = fill + stroke (crisp, visible)
        ]
        nsView.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
    }
}

// MARK: - 6. Image fold (subtle 3D unroll reveal, NOT a shader)

/// Subtle rotation3D unroll on appear for the banner image. A few degrees
/// only — a reveal, not a gimmick.
struct ImageFoldReveal<Content: View>: View {
    let content: Content
    @State private var appeared = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .rotation3DEffect(
                .degrees(VoxflowMotion.reduceMotion ? 0 : (appeared ? 0 : 7)),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top
            )
            .opacity(VoxflowMotion.reduceMotion ? 1 : (appeared ? 1 : 0))
            .animation(
                VoxflowMotion.reduceMotion ? nil :
                    .spring(response: 0.5, dampingFraction: 0.85),
                value: appeared
            )
            .onAppear { appeared = true }
    }
}

// MARK: - 7. Floating icons (ambient, slow, pauses when window not key)

/// A few soft mic/wave glyphs drifting slowly upward in the banner /
/// empty states. Low count, low opacity, pauses when the window is not
/// key (controlActiveState), so it never burns cycles in the background.
struct FloatingIconsView: View {
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var phase = false

    private let icons = ["mic.fill", "waveform", "mic.fill", "waveform.path"]

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: controlActiveState != .key || VoxflowMotion.reduceMotion
        )) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 28) {
                ForEach(Array(icons.enumerated()), id: \.offset) { index, name in
                    Image(systemName: name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .offset(
                            x: CGFloat(sin(t * 0.35 + Double(index) * 1.7)) * 5,
                            y: CGFloat(sin(t * 0.5 + Double(index) * 2.1)) * 7
                        )
                        .opacity(0.55)
                }
            }
            .allowsHitTesting(false)
        }
        .onAppear { phase = true }
    }
}

// MARK: - 8. Cosmic gradient (banner ONLY, animated mesh, low opacity)

/// Slow animated gradient mesh for the banner ONLY — never full-window,
/// never behind text lists. SwiftUI Canvas + TimelineView, no WebGL.
struct CosmicGradientView: View {
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 20.0,
            paused: controlActiveState != .key || VoxflowMotion.reduceMotion
        )) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let blobs: [(x: CGFloat, y: CGFloat, r: CGFloat, color: Color)] = [
                    (0.22 + 0.05 * CGFloat(sin(t * 0.11)), 0.30, 0.55, .voxflowAmber),
                    (0.78 + 0.05 * CGFloat(cos(t * 0.09)), 0.35, 0.60, .voxflowCoral),
                    (0.55 + 0.04 * CGFloat(sin(t * 0.07 + 2)), 0.75, 0.50, Color(red: 0.88, green: 0.73, blue: 0.89)),
                    (0.35 + 0.04 * CGFloat(cos(t * 0.08 + 4)), 0.65, 0.45, Color(red: 1.0, green: 0.71, blue: 0.76)),
                ]
                for blob in blobs {
                    let rect = CGRect(
                        x: blob.x * size.width - blob.r * size.width,
                        y: blob.y * size.height - blob.r * size.width,
                        width: blob.r * size.width * 2,
                        height: blob.r * size.width * 2
                    )
                    ctx.fill(Path(ellipseIn: rect), with: .color(blob.color.opacity(0.30)))
                }
            }
        }
        .blur(radius: 28)
        .allowsHitTesting(false)
    }
}

// MARK: - 9a. Letter drop (wordmark, one-time, subtle)

/// One-time per-letter drop for the app wordmark on launch. Subtle
/// (10pt), springy, no repeat.
struct LetterDropWordmark: View {
    let text: String
    let font: Font
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(font)
                    .offset(y: VoxflowMotion.reduceMotion ? 0 : (appeared ? 0 : -10))
                    .opacity(VoxflowMotion.reduceMotion ? 1 : (appeared ? 1 : 0))
                    .animation(
                        VoxflowMotion.reduceMotion ? nil :
                            .spring(response: 0.3, dampingFraction: 0.75)
                            .delay(min(Double(index) * VoxflowMotion.staggerStep, 0.32)),
                        value: appeared
                    )
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - 9b. Interactive grid → hover highlight on stat cards

/// Hover highlight for stat/insight cards: a soft brightening + hairline
/// lift on hover. No grid, no cursor follower — native onHover only.
struct HoverHighlightCard<Content: View>: View {
    let content: Content
    @State private var hovering = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(hovering ? 0.18 : 0.06), lineWidth: 1)
            )
            .scaleEffect(hovering ? 1.01 : 1.0)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Pearl button (glossy black pill, primary CTAs only)

/// Glossy black pill with layered inner highlights, a soft outer shadow,
/// a sparkle swap on hover, and a slight press-down on active. Native
/// SwiftUI ButtonStyle — no web code. Apply to PRIMARY actions only
/// (Start Dictating, banner primary action, key confirmations). NEVER
/// on destructive actions, tiny icon buttons, toggles, or menu items.
struct PearlButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        PearlButtonContent(configuration: configuration, isEnabled: isEnabled)
    }
}

private struct PearlButtonContent: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Base glossy black pill.
                    Capsule().fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.22, blue: 0.24),
                                Color.black,
                                Color(red: 0.05, green: 0.05, blue: 0.06),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // Top inner highlight (the "pearl" gloss).
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(hovering ? 0.34 : 0.24), Color.white.opacity(0)],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .padding(.bottom, 8)
                    // Bottom inner shade.
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.45)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                        .padding(.top, 10)
                }
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(hovering ? 0.28 : 0.16), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.28), radius: hovering ? 10 : 6, x: 0, y: hovering ? 5 : 3)
            .overlay(alignment: .trailing) {
                // Sparkle swap on hover: a small sparkle fades in.
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovering ? 0.95 : 0))
                    .padding(.trailing, 12)
            }
            // Full-rect hit area: clicking ANYWHERE on the button —
            // its background, its gloss, or its text label — must fire
            // the action. Without an explicit contentShape, decorative
            // overlays can shrink the hit area on macOS.
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .opacity(isEnabled ? 1 : 0.55)
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == PearlButtonStyle {
    static var pearl: PearlButtonStyle { PearlButtonStyle() }
}

// MARK: - Apple glass button styles (secondary / prominent / destructive)
//
// Verse's hierarchy: pearl = primary CTAs; Apple glass = everything else.
// `.buttonStyle(.glass)` / `.glassProminent` are macOS 26+ Liquid Glass
// APIs. Voxflow targets macOS 13+ and CI's Check workflow runs on
// macos-15 (Xcode 16, SDK 15), where those symbols do not exist at all —
// a direct reference would not even compile on CI, and @available alone
// cannot fix a missing SDK symbol. So these are native SwiftUI shims
// that reproduce the glass look (translucent material + hairline stroke
// + soft shadow + press dim) on every supported macOS, with no
// deployment-target change. If the deployment target ever rises to
// macOS 26+, these can delegate to the real .glass styles.

/// Translucent secondary button: frosted material, hairline stroke.
struct VoxflowGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
            )
            // Full-rect hit area (see PearlButtonStyle): the whole
            // button — background, stroke, and text — must fire.
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Secondary-prominent button: filled glass with a stronger tint.
struct VoxflowGlassProminentButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.92), tint.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: tint.opacity(0.35), radius: 8, x: 0, y: 3)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.75)
            )
            // Full-rect hit area (see PearlButtonStyle): the whole
            // button — background, stroke, and text — must fire.
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == VoxflowGlassButtonStyle {
    /// Secondary glass button (frosted, translucent).
    static var voxflowGlass: VoxflowGlassButtonStyle { VoxflowGlassButtonStyle() }
}

extension ButtonStyle where Self == VoxflowGlassProminentButtonStyle {
    /// Secondary-prominent glass button.
    static var voxflowGlassProminent: VoxflowGlassProminentButtonStyle {
        VoxflowGlassProminentButtonStyle()
    }
    /// Destructive glass button: red-tinted prominent (Clear history, delete).
    static var voxflowGlassDestructive: VoxflowGlassProminentButtonStyle {
        VoxflowGlassProminentButtonStyle(tint: .red)
    }
}
