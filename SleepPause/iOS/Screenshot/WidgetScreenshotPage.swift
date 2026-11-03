import SwiftUI
import WidgetKit

/// The real widget view, rendered in the app process so the simulator can photograph it.
/// SpringBoard will not host an extension during CI.
struct WidgetScreenshotPage: View {
    private var entry: ZoneEntry {
        ZoneEntry(date: Date(), snapshot: .placeholder)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text("小组件")
                    .font(.largeTitle.bold())
                HStack(alignment: .top, spacing: 16) {
                    tile(family: .systemSmall)
                    Spacer(minLength: 0)
                }
                tile(family: .systemMedium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
            .padding(24)
        }
    }

    private func tile(family: WidgetFamily) -> some View {
        ZoneWidgetView(entry: entry, familyOverride: family, renderingOverride: .fullColor)
            .padding(12)
            .frame(maxWidth: family == .systemMedium ? .infinity : 170,
                   minHeight: family == .systemMedium ? 158 : 158,
                   alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
