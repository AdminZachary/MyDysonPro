import SwiftUI
import UIKit

// MARK: - System colors
// Semantic colors only. Sleep is indigo, air is teal, levels match Health.

enum Palette {
    static var canvas: Color { Color(uiColor: .systemGroupedBackground) }
    static var surface: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var ink: Color { .primary }
    static var secondaryInk: Color { .secondary }
    static var hairline: Color { Color(uiColor: .separator) }
    static var blue: Color { .indigo }
    static var yellow: Color { .yellow }
    static var red: Color { .red }
    static var focus: Color { .orange }

    static let levels: [Color] = LevelPalette.levels
    static let unknown = Color.secondary
    static func level(_ l: Int?) -> Color { LevelPalette.color(l) }
    static let levelNames = LevelPalette.names

    static var night: Color { .black }
    static var dusk: Color { .indigo }
    static var moon: Color { .indigo }
}

/// Sleep accent. System indigo on the grouped background, not a custom palette.
enum Night {
    static var ground: Color { .black }
    static var surface: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var ink: Color { .primary }
    static var muted: Color { .secondary }
    static var accent: Color { .indigo }
    static var onAccent: Color { .white }
    static var danger: Color { .red }
}

// MARK: - Liquid Glass
// Used the way system apps do: prominent buttons and floating controls.
// Lists and forms keep the system grouped background.

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
                } else {
                    content.background(shape.fill(.ultraThinMaterial))
                }
            }
            .overlay(shape.strokeBorder(env.wantsBorder ? Color.primary.opacity(0.55) : Color.clear,
                                        lineWidth: env.wantsBorder ? 1.5 : 0))
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

extension View {
    func card(tint: Color? = nil, prominent: Bool = false) -> some View { self }
    func nightCard() -> some View { self }

    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, prominent: Bool = false, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, prominent: prominent, interactive: interactive))
    }

    func floatingRow() -> some View { self }

    @ViewBuilder
    func glassID<ID: Hashable & Sendable>(_ id: ID, in ns: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) { glassEffectID(id, in: ns) } else { self }
    }

    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    func touchTarget(minHeight: CGFloat = 44) -> some View {
        frame(minHeight: minHeight).contentShape(Rectangle())
    }

    func paperBackdrop(_ stripe: Color = .indigo) -> some View {
        listStyle(.insetGrouped)
    }

    func nightBackdrop() -> some View {
        listStyle(.insetGrouped)
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
    var tint: Color = .indigo
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }
}

struct UnverifiedBadge: View {
    var text = "未验证"
    var body: some View {
        Label(text, systemImage: "questionmark.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .accessibilityLabel("数据来源未验证")
    }
}

/// Health-style air summary: a teal symbol, the category title, and the level word.
struct AirOrb: View {
    var level: Int?
    var label: String
    var sublabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("空气", systemImage: "aqi.medium")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.teal)
            Text(label)
                .font(.title2.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            LevelMark(level: level)
            if let sublabel {
                Text(sublabel).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Health-style dose: a rounded number, a Loud/OK caption, and the level symbol.
struct DoseBar: View {
    var percent: Double?

    private var level: Int? {
        guard let p = percent else { return nil }
        return p < 50 ? 0 : p < 80 ? 1 : p < 100 ? 2 : 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("噪音剂量", systemImage: "ear.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(percent.map { String(format: "%.0f", $0) } ?? "–")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("%").font(.subheadline).foregroundStyle(.secondary)
            }
            Text(level.map { LevelPalette.name($0) } ?? "暂无")
                .font(.caption)
                .foregroundStyle(.secondary)
            LevelMark(level: level)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(percent.map { "今日噪音剂量 \(Int($0))%，\(LevelPalette.name(level))" } ?? "今日噪音剂量未知")
    }
}

struct StatePanel: View {
    var symbol: String
    var title: String
    var message: String
    var tint: Color = .indigo
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .glassButton(prominent: true)
                    .tint(tint)
                    .touchTarget()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func night() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.3) }
}
