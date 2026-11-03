import SwiftUI
import UIKit

/// Levels follow Health and the Noise app: green, yellow, orange, red,
/// always with a word and an SF Symbol so color is not the only signal.
enum LevelPalette {
    static let names = ["好", "一般", "偏高", "差"]

    static func color(_ level: Int?) -> Color {
        switch level {
        case 0: return .green
        case 1: return .yellow
        case 2: return .orange
        case 3: return .red
        default: return .secondary
        }
    }

    static func symbol(_ level: Int?) -> String {
        switch level {
        case 0: return "checkmark.circle.fill"
        case 1: return "minus.circle.fill"
        case 2: return "exclamationmark.triangle.fill"
        case 3: return "ear.trianglebadge.exclamationmark"
        default: return "questionmark.circle"
        }
    }

    /// Noise app wording: OK under 80 dB, Loud at or above.
    static func loudLabel(_ db: Double?) -> String {
        guard let db else { return "–" }
        return db >= 80 ? "偏响" : "正常"
    }

    static func name(_ level: Int?) -> String {
        guard let level, names.indices.contains(level) else { return "未知" }
        return names[level]
    }

    static var levels: [Color] { (0..<4).map { color($0) } }

    static var canvas: Color { Color(uiColor: .systemGroupedBackground) }
    static var ink: Color { .primary }
    static var secondary: Color { .secondary }
}

/// Symbol plus the level word, the same idea as Health category rows.
struct LevelMark: View {
    var level: Int?
    var showsName = true

    var body: some View {
        Label {
            if showsName {
                Text(LevelPalette.name(level))
                    .font(.subheadline.weight(.semibold))
            }
        } icon: {
            Image(systemName: LevelPalette.symbol(level))
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(LevelPalette.color(level))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LevelPalette.name(level))
    }
}
