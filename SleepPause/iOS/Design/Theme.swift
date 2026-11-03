import SwiftUI
import UIKit

// MARK: - Palette
// Bauhaus primaries on paper, shared with widgets via LevelPalette.
// Sleep screens use `Night` (fixed warm dark) and do not follow a bright blue accent.
// Contrast ratios: docs/DESIGN.md.

enum Palette {
    static var canvas: Color { LevelPalette.canvas }
    static var surface: Color { LevelPalette.surface }
    static var ink: Color { LevelPalette.ink }
    static var secondaryInk: Color { LevelPalette.secondary }
    static var hairline: Color { LevelPalette.hairline }
    static var blue: Color { LevelPalette.color(0) }
    static var yellow: Color { LevelPalette.color(1) }
    static var red: Color { LevelPalette.color(2) }

    /// Primary action color on day screens (Bauhaus blue). Not used at bedtime.
    static var focus: Color { blue }

    static let levels: [Color] = LevelPalette.levels
    static let unknown = LevelPalette.secondary
    static func level(_ l: Int?) -> Color { LevelPalette.color(l) }
    static let levelNames = LevelPalette.names

    // Night-screen aliases so a missed call site stays warm rather than indigo.
    static var night: Color { Night.ground }
    static var dusk: Color { Night.surface }
    static var moon: Color { Night.accent }
}

/// Bedtime palette. Fixed colors: dim, warm, no blue-white. See docs/DESIGN.md.
enum Night {
    static let ground = LevelPalette.fixed(0x110C0A)
    static let surface = LevelPalette.fixed(0x1C1410)
    static let ink = LevelPalette.fixed(0xE7C7A8)
    static let muted = LevelPalette.fixed(0xB89A80)
    static let accent = LevelPalette.fixed(0xD47848)
    static let onAccent = LevelPalette.fixed(0x110C0A)
    static let danger = LevelPalette.fixed(0xC96B5A)
}

// MARK: - Liquid Glass
// Glass stays on controls (buttons, the system tab bar and navigation bar).
// Content cards are flat solids. Availability matches the iOS 26 SDK.

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

/// Glass for a control shape. Do not use this for content cards.
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
                    content.background(shape.fill(Color(uiColor: .secondarySystemBackground)))
                        .background(shape.fill((prominent ? tint : nil)?.opacity(0.18) ?? .clear))
                } else {
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
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: .leading) {
                if let tint { Rectangle().fill(tint).frame(width: 6) }
            }
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(prominent ? Palette.ink : Palette.hairline, lineWidth: prominent ? 1.5 : 1))
    }
}

struct NightCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Night.surface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Night.muted.opacity(0.45), lineWidth: 1))
    }
}

extension View {
    /// Flat content card. `tint` is a left rule for state, not a wash.
    func card(tint: Color? = nil, prominent: Bool = false) -> some View {
        modifier(CardModifier(tint: tint, prominent: prominent))
    }

    func nightCard() -> some View { modifier(NightCardModifier()) }

    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, prominent: Bool = false, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, prominent: prominent, interactive: interactive))
    }

    func floatingRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)).listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    func glassID<ID: Hashable & Sendable>(_ id: ID, in ns: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) { glassEffectID(id, in: ns) } else { self }
    }

    /// Primary / secondary controls. Content cards do not use this.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// Minimum touch target. 44 pt on iPhone, pass 40 on watch call sites that use this helper.
    func touchTarget(minHeight: CGFloat = 44) -> some View {
        frame(minHeight: minHeight).contentShape(Rectangle())
    }
}

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
    var tint: Color = Palette.blue
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(tint, lineWidth: 1.5))
    }
}

struct UnverifiedBadge: View {
    var text = "未验证"
    var body: some View {
        Label(text, systemImage: "questionmark.diamond")
            .font(.caption.weight(.bold))
            .foregroundStyle(LevelPalette.fixed(0x1A1814))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 2).fill(LevelPalette.fixed(0xA67C00)))
            .accessibilityLabel("数据来源未验证")
    }
}

/// Flat paper page with one primary stripe. No gradient.
struct PaperBackdrop: View {
    var stripe: Color = Palette.blue
    var body: some View {
        ZStack(alignment: .top) {
            Palette.canvas
            stripe.frame(height: 8).frame(maxWidth: .infinity)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func paperBackdrop(_ stripe: Color = Palette.blue) -> some View {
        scrollContentBackground(.hidden).background(PaperBackdrop(stripe: stripe))
    }

    func nightBackdrop() -> some View {
        scrollContentBackground(.hidden).background(Night.ground.ignoresSafeArea())
    }
}

// MARK: - Signature visuals

/// Flat circle for air quality. The word inside the circle repeats the level
/// so the color is not the only signal. Static: no breathing animation.
struct AirOrb: View {
    var level: Int?
    var label: String
    var sublabel: String?
    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 96

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(LevelPalette.color(level))
                Text(LevelPalette.name(level))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevelPalette.labelColor(level))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(width: diameter, height: diameter)
            Text(label)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if let sublabel {
                Text(sublabel).font(.caption).foregroundStyle(Palette.secondaryInk).multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Segmented square bar for the daily noise dose. Four cells, plus the number and the level word.
struct DoseBar: View {
    var percent: Double?

    private var level: Int? {
        guard let p = percent else { return nil }
        return p < 50 ? 0 : p < 80 ? 1 : p < 100 ? 2 : 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(percent.map { String(format: "%.0f%%", $0) } ?? "–")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("噪音剂量")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.secondaryInk)
            }
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(segmentFill(index))
                        .frame(height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.hairline, lineWidth: 1))
                }
            }
            LevelMark(level: level)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percent.map { "今日噪音剂量 \(Int($0))%，\(LevelPalette.name(level))" } ?? "今日噪音剂量未知")
    }

    private func segmentFill(_ index: Int) -> Color {
        guard let p = percent else { return Palette.hairline }
        let filled = Int((min(max(p, 0), 100) / 25).rounded(.up))
        return index < filled ? LevelPalette.color(level) : Palette.hairline
    }
}

struct StatePanel: View {
    var symbol: String
    var title: String
    var message: String
    var tint: Color = Palette.blue
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(LevelPalette.labelColor(0))
                .frame(width: 44, height: 44)
                .background(tint, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(title).font(.title3.weight(.bold)).foregroundStyle(Palette.ink)
            Text(message).font(.body).foregroundStyle(Palette.secondaryInk).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .glassButton(prominent: true)
                    .tint(Palette.blue)
                    .touchTarget()
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

// MARK: - Haptics

@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }

    /// Bedtime screens. Soft and quiet so a tap does not jolt a dark-adapted person.
    static func night() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.3) }
}
