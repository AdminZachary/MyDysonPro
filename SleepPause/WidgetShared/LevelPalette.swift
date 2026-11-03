import SwiftUI
import UIKit

/// Bauhaus status palette shared by the app, widgets and Live Activity.
/// Good / moderate / poor / bad are never color alone: each level is a primary
/// (blue, ochre, red, black) plus a circle, square, triangle or crossed square,
/// and a word. Hex values and contrast ratios live in `docs/DESIGN.md`.
enum LevelPalette {
    static let names = ["好", "一般", "偏高", "差"]

    static func ui(_ rgb: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
                green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
                blue: CGFloat(rgb & 0xFF) / 255.0,
                alpha: alpha)
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            ui(trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func fixed(_ rgb: UInt32) -> Color { Color(uiColor: ui(rgb)) }

    /// Page background. Light paper / dark ground.
    static let canvas = dynamic(light: 0xF3EFE6, dark: 0x12110F)
    /// Cards and grouped content.
    static let surface = dynamic(light: 0xFBF8F1, dark: 0x1C1A17)
    /// Primary text.
    static let ink = dynamic(light: 0x1A1814, dark: 0xF4F0E6)
    /// Secondary text. Both pairs are above 4.5:1.
    static let secondary = dynamic(light: 0x4A453C, dark: 0xC9BBA8)
    /// Rules and empty dose segments. Not used for text.
    static let hairline = dynamic(light: 0xD9D2C5, dark: 0x3A342C)

    /// The four status fills. Index 0 good … 3 bad. Nil draws the unknown gray.
    static func color(_ level: Int?) -> Color {
        switch level {
        case 0: return dynamic(light: 0x1E4B99, dark: 0xA9C4F5)   // blue
        case 1: return dynamic(light: 0xA67C00, dark: 0xF0D078)   // ochre
        case 2: return dynamic(light: 0xB42318, dark: 0xFFB4A8)   // red
        case 3: return dynamic(light: 0x1A1814, dark: 0xF4F0E6)   // black / paper
        default: return secondary
        }
    }

    /// Text that sits on `color(_:)`. Ochre always takes near-black; the others
    /// flip with the mode so the word stays on the filled shape.
    static func labelColor(_ level: Int?) -> Color {
        if level == 1 { return fixed(0x1A1814) }
        return dynamic(light: 0xF3EFE6, dark: 0x1A1814)
    }

    static func name(_ level: Int?) -> String {
        guard let level, names.indices.contains(level) else { return "未知" }
        return names[level]
    }

    static var levels: [Color] { (0..<4).map { color($0) } }

    /// Warm near-black used by the sleep screens. Widgets use `canvas` instead.
    static let night = fixed(0x110C0A)
}

/// Circle, square, triangle, crossed square. The word is part of the mark.
struct LevelMark: View {
    var level: Int?
    var showsName = true

    var body: some View {
        HStack(spacing: 6) {
            shape
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            if showsName {
                Text(LevelPalette.name(level))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LevelPalette.ink)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LevelPalette.name(level))
    }

    @ViewBuilder private var shape: some View {
        let fill = LevelPalette.color(level)
        switch level {
        case 0:
            Circle().fill(fill)
        case 1:
            RoundedRectangle(cornerRadius: 1, style: .continuous).fill(fill)
        case 2:
            Triangle().fill(fill)
        case 3:
            ZStack {
                RoundedRectangle(cornerRadius: 1, style: .continuous).fill(fill)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(LevelPalette.labelColor(3))
            }
        default:
            Circle().strokeBorder(fill, lineWidth: 1.5)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
