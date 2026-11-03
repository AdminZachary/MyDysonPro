import SwiftUI
import UserNotifications

/// First-launch walkthrough. Paper Bauhaus page, one primary button at the bottom.
struct OnboardingView: View {
    @AppStorage("onboarding.done") private var done = false
    @EnvironmentObject var model: AppModel
    @State private var page = 0
    @State private var granted: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                install.tag(1)
                permissions.tag(2)
                zone.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < 3 { page += 1; Haptics.select() } else { done = true; Haptics.success() }
            } label: {
                Text(page < 3 ? "继续" : "开始使用")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .glassButton(prominent: true)
            .tint(Palette.blue)
            .touchTarget()
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Button("跳过") { done = true }
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .touchTarget()
                .padding(.bottom, 4)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
    }

    private func pageView<Content: View>(_ symbol: String, _ title: String, _ subtitle: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(LevelPalette.labelColor(0))
                    .frame(width: 64, height: 64)
                    .background(Palette.blue, in: RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 28)
                Text(title).font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.body).foregroundStyle(Palette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var welcome: some View {
        pageView("moon.zzz.fill", "睡着了，音乐自动停", "Apple Watch 判断你入睡，iPhone 暂停播放。降噪整晚保持开启。") {
            VStack(alignment: .leading, spacing: 12) {
                row("applewatch", "手表：心率 + 静止判断入睡，可选智能闹钟")
                row("iphone", "iPhone：暂停任何 App 的播放，早上给你一份小结")
                row("headphones", "Dyson Zone（可选）：空气、噪音、风扇、降噪")
            }
            .card()
        }
    }

    private var install: some View {
        pageView("hammer.fill", "安装到手机和手表", "这是自己编译的 App，需要先在 Xcode 里签名。") {
            VStack(alignment: .leading, spacing: 12) {
                row("1.circle.fill", "Xcode → 每个 target 的 Signing 里选你的 Team（共 4 个：App、手表、两个小组件）")
                row("2.circle.fill", "project.yml 里把 BASE_BUNDLE_ID 改成你自己的，比如 com.zheng.sleeppause")
                row("3.circle.fill", "iPhone 上的 Watch App → 找到 SleepPause → 安装")
                row("4.circle.fill", "免费账号签名 7 天后过期，需要重新运行一次")
                HStack {
                    Image(systemName: model.watchAppInstalled ? "checkmark.seal.fill" : "applewatch.slash")
                        .foregroundStyle(model.watchAppInstalled ? Palette.blue : Palette.red)
                    Text(model.watchAppInstalled ? "已检测到手表 App" : "还没检测到手表 App").font(.footnote)
                }
            }
            .card()
        }
        .onAppear { model.refreshWatchState() }
    }

    private var permissions: some View {
        pageView("lock.shield.fill", "需要的权限", "都只在本机使用，可以随时在设置里关闭。") {
            VStack(spacing: 10) {
                permButton("heart.fill", "健康（心率、睡眠、环境声音）", "health") {
                    await model.requestHealthAuthorization(); return true
                }
                permButton("bell.badge.fill", "通知（早安小结、专注、提醒）", "notif") {
                    (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
                }
                permButton("music.note", "Apple Music 控制（可选）", "music") {
                    await model.requestMusicAuthorization(); return true
                }
                Text("蓝牙和定位会在你用到 Zone、通勤地图时再询问。")
                    .font(.caption).foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private var zone: some View {
        pageView("headphones", "我的耳机", "选你平时戴的那一副。以后可以在睡眠页的“选项”里改。") {
            HeadphonePicker(suggested: HeadphoneRoute.suggestion())
                .card()
        }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Palette.blue).frame(width: 24)
        }
    }

    private func permButton(_ symbol: String, _ title: String, _ key: String, _ ask: @escaping () async -> Bool) -> some View {
        Button {
            Task { if await ask() { granted.insert(key); Haptics.success() } }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 28).foregroundStyle(Palette.blue)
                Text(title).multilineTextAlignment(.leading).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Image(systemName: granted.contains(key) ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(granted.contains(key) ? Palette.blue : Palette.secondaryInk)
            }
            .padding(.horizontal, 12)
            .touchTarget()
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
