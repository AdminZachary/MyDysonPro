import SwiftUI
import UIKit

// MARK: - Palette
// One visual language for the app, widgets and Live Activity: calm night indigo for sleep,
// green → yellow → orange → red for air / noise levels (same bands as the commute map).

enum Palette {
    static let night = Color(red: 0.07, green: 0.08, blue: 0.20)
    static let dusk = Color(red: 0.20, green: 0.16, blue: 0.45)
    static let moon = Color(red: 0.78, green: 0.80, blue: 1.00)
    static let focus = Color(red: 0.98, green: 0.45, blue: 0.30)

    static let levels: [Color] = LevelPalette.levels   // shared with widgets / Live Activity
    static let unknown = Color.gray

    static func level(_ l: Int?) -> Color { l.map { levels[min(3, max(0, $0))] } ?? unknown }

    static func levelGradient(_ l: Int?) -> LinearGradient {
        let c = level(l)
        return LinearGradient(colors: [c.opacity(0.95), c.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Vivid air-level backdrop for the dashboard (content layer under glass chips). Keeps white text legible.
    static func levelBackdrop(_ l: Int?) -> LinearGradient {
        guard let l else { return LinearGradient(colors: [dusk, night], startPoint: .topLeading, endPoint: .bottomTrailing) }
        return LinearGradient(colors: [level(l).opacity(0.9), dusk, night], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let nightGradient = LinearGradient(colors: [night, dusk], startPoint: .top, endPoint: .bottom)
    static let levelNames = ["好", "一般", "偏高", "差"]
}

// MARK: - Liquid Glass (iOS 26+) with a material / solid fallback
//
// APIs (Apple docs, confirmed against the current SwiftUI reference):
//   View.glassEffect(_:in:)            https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
//   Glass.regular / .clear / .tint(_:) / .interactive(_:)   https://developer.apple.com/documentation/swiftui/glass
//   GlassEffectContainer(spacing:content:)  https://developer.apple.com/documentation/swiftui/glasseffectcontainer
//   View.glassEffectID(_:in:)          https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)
//   .buttonStyle(.glass / .glassProminent)  https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass
// Rules we follow (HIG / "Applying Liquid Glass to custom views"): glass only on the functional
// layer, tint only for primary actions and air-level state, adjacent glass grouped in one container.

/// Whether custom glass should be drawn as glass (iOS 26+, Reduce Transparency off).
struct GlassStyleEnvironment {
    var reduceTransparency: Bool
    var increasedContrast: Bool
    var showBorders: Bool
    var wantsBorder: Bool { increasedContrast || showBorders }
}

private struct GlassEnvReader<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityShowBorders) private var showBorders
    var content: (GlassStyleEnvironment) -> Content
    var body: some View {
        content(GlassStyleEnvironment(reduceTransparency: reduceTransparency,
                                      increasedContrast: contrast == .increased, showBorders: showBorders))
    }
}

/// Glass surface in any shape. `tint` is only applied when `prominent` (primary action / air state).
struct GlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color? = nil
    var prominent = false
    var interactive = false

    func body(content: Content) -> some View {
        GlassEnvReader { env in
            Group {
                if #available(iOS 26.0, *), !env.reduceTransparency {
                    content.glassEffect(glass, in: shape)
                } else if env.reduceTransparency {
                    // Solid fallback: no translucency at all.
                    content.background(shape.fill(Color(uiColor: .secondarySystemBackground)))
                        .background(shape.fill((prominent ? tint : nil)?.opacity(0.18) ?? .clear))
                } else {
                    // iOS 17–25: the previous material look.
                    content.background(shape.fill(.ultraThinMaterial))
                        .background(shape.fill((prominent ? tint : nil)?.opacity(0.15) ?? .clear))
                }
            }
            .overlay(shape.strokeBorder(env.wantsBorder ? Color.primary.opacity(0.55) : Color.white.opacity(0.08),
                                        lineWidth: env.wantsBorder ? 1.5 : 0.5))
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var g: Glass = .regular
        if prominent, let tint { g = g.tint(tint.opacity(0.55)) }
        if interactive { g = g.interactive() }
        return g
    }
}

struct CardModifier: ViewModifier {
    var tint: Color? = nil
    var prominent = false
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: 26, style: .continuous), tint: tint, prominent: prominent))
    }
}

extension View {
    /// Glass card. `tint` only colours the glass when `prominent` is true (air-level state, primary action).
    func card(tint: Color? = nil, prominent: Bool = false) -> some View { modifier(CardModifier(tint: tint, prominent: prominent)) }

    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, prominent: Bool = false, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, prominent: prominent, interactive: interactive))
    }

    /// Use inside a List/Form to let a card float without the grouped-row chrome.
    func floatingRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)).listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Morph identity inside a `GlassGroup` (no-op before iOS 26).
    @ViewBuilder
    func glassID<ID: Hashable & Sendable>(_ id: ID, in ns: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) { glassEffectID(id, in: ns) } else { self }
    }

    /// Primary / secondary buttons: `.glassProminent` / `.glass` on iOS 26+, bordered styles before.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

/// Groups adjacent glass so it samples one region and can morph (GlassEffectContainer on iOS 26+).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

struct Chip: View {
    var symbol: String
    var text: String
    var tint: Color = .accentColor
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .glassSurface(Capsule(), interactive: true)        // untinted glass; colour lives in the glyph
    }
}

/// Small orange "未验证" capsule used everywhere data comes from inferred fields (solid, never glass,
/// so the warning stays legible on any background).
struct UnverifiedBadge: View {
    var text = "未验证"
    var body: some View {
        Label(text, systemImage: "questionmark.diamond")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color.orange.opacity(0.22)))
            .foregroundStyle(.orange)
            .accessibilityLabel("数据来源未验证")
    }
}

/// Soft colour wash behind a tab's list so glass cards have something to refract, fading into the
/// normal grouped background (keeps system rows legible in light and dark mode).
struct VividBackdrop: View {
    var color: Color = Palette.dusk
    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
            LinearGradient(colors: [color.opacity(0.65), color.opacity(0.25), .clear],
                           startPoint: .top, endPoint: .center)
            RadialGradient(colors: [Palette.moon.opacity(0.25), .clear], center: .topTrailing, startRadius: 10, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// List / Form over a `VividBackdrop`.
    func vividBackdrop(_ color: Color) -> some View {
        scrollContentBackground(.hidden).background(VividBackdrop(color: color))
    }
}

// MARK: - Signature visuals

/// Air-quality "breathing" orb: color = level, slow breathing animation (stops with Reduce Motion).
struct BreathingOrb: View {
    var level: Int?
    var label: String
    var sublabel: String?
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Palette.level(level).opacity(0.9), Palette.level(level).opacity(0.15)],
                                     center: .center, startRadius: 4, endRadius: 80))
                .scaleEffect(breathe ? 1.06 : 0.92)
                .blur(radius: 2)
            Circle().strokeBorder(Palette.level(level).opacity(0.5), lineWidth: 1)
            VStack(spacing: 2) {
                Image(systemName: level == nil ? "aqi.medium" : level! <= 1 ? "leaf.fill" : "aqi.high")
                    .font(.title2)
                    .symbolEffect(.pulse, options: .repeating, isActive: level.map { $0 >= 2 } ?? false)
                Text(label).font(.headline)
                if let sublabel { Text(sublabel).font(.caption2).foregroundStyle(.secondary) }
            }
            .foregroundStyle(.primary)
        }
        .frame(width: 130, height: 130)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Animated ring for the daily noise dose (0–100 %+, wraps in red above 100 %).
struct DoseRing: View {
    var percent: Double?
    var lineWidth: CGFloat = 12
    @State private var shown: Double = 0

    var body: some View {
        let p = percent ?? 0
        let lvl = p < 50 ? 0 : p < 80 ? 1 : p < 100 ? 2 : 3
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, shown / 100))
                .stroke(AngularGradient(colors: [Palette.levels[0], Palette.level(lvl)], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(percent.map { String(format: "%.0f%%", $0) } ?? "–").font(.title3.bold()).monospacedDigit()
                Text("噪音剂量").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 74, height: 74)
            .glassSurface(Circle())          // glass lens over the ring centre
        }
        .frame(width: 110, height: 110)
        .onAppear { withAnimation(.spring(duration: 1.2)) { shown = p } }
        .onChange(of: p) { _, v in withAnimation(.spring(duration: 0.8)) { shown = v } }
        .accessibilityLabel("今日噪音剂量 \(Int(p)) %")
    }
}

/// Empty / error / info states with one primary action.
struct StatePanel: View {
    var symbol: String
    var title: String
    var message: String
    var tint: Color = .accentColor
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: title)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).glassButton(prominent: true).tint(tint).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Haptics

@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}
