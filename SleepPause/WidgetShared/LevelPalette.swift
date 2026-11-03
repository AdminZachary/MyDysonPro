import SwiftUI

/// Shared level colors (app, widgets, Live Activity): good → fair → elevated → bad.
enum LevelPalette {
    static let levels: [Color] = [
        Color(red: 0.20, green: 0.78, blue: 0.55),
        Color(red: 0.98, green: 0.80, blue: 0.25),
        Color(red: 0.98, green: 0.55, blue: 0.20),
        Color(red: 0.93, green: 0.27, blue: 0.33),
    ]
    static let night = Color(red: 0.07, green: 0.08, blue: 0.20)
    static let dusk = Color(red: 0.20, green: 0.16, blue: 0.45)

    static func color(_ l: Int?) -> Color { l.map { levels[min(3, max(0, $0))] } ?? .gray }

    static func background(_ l: Int?) -> LinearGradient {
        guard let l else { return LinearGradient(colors: [night, dusk], startPoint: .top, endPoint: .bottom) }
        let c = color(l)
        return LinearGradient(colors: [c.opacity(0.55), night.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
