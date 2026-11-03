import SwiftUI
import UserNotifications

/// First-launch walkthrough: what the app does, Xcode Team / watch install, permissions, optional Zone.
struct OnboardingView: View {
    @AppStorage("onboarding.done") private var done = false
    @EnvironmentObject var model: AppModel
    @State private var page = 0
    @State private var granted: Set<String> = []

    var body: some View {
        ZStack {
            Palette.nightGradient.ignoresSafeArea()
            // A couple of soft colour blooms so the glass panels have something to refract.
            Circle().fill(Palette.dusk).frame(width: 320).blur(radius: 60).offset(x: 120, y: -260)
            Circle().fill(Palette.focus.opacity(0.35)).frame(width: 260).blur(radius: 70).offset(x: -140, y: 240)
            VStack {
                TabView(selection: $page) {
                    welcome.tag(0)
                    install.tag(1)
                    permissions.tag(2)
                    zone.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.smooth, value: page)

                Button {
                    if page < 3 { page += 1; Haptics.select() } else { done = true; Haptics.success() }
                } label: {
                    Text(page < 3 ? "继续" : "开始使用").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .glassButton(prominent: true).tint(Palette.moon).foregroundStyle(Palette.night)
                .controlSize(.large)
                .padding(.horizontal, 24)
                Button("跳过") { done = true }.font(.footnote).foregroundStyle(.white.opacity(0.6)).padding(.bottom, 8)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private func pageView<Content: View>(_ symbol: String, _ title: String, _ subtitle: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: symbol).font(.system(size: 64)).foregroundStyle(Palette.moon)
                    .symbolEffect(.bounce, value: page)
                    .padding(.top, 40)
                Text(title).font(.title.bold()).multilineTextAlignment(.center)
                Text(subtitle).font(.body).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                content()
            }
            .padding(24)
        }
    }

    private var welcome: some View {
        pageView("moon.zzz.fill", "睡着了，音乐自动停", "Apple Watch 判断你入睡，iPhone 暂停播放。降噪整晚保持开启。") {
            VStack(alignment: .leading, spacing: 12) {
                row("applewatch", "手表：心率 + 静止判断入睡，可选智能闹钟")
                row("iphone", "iPhone：暂停任何 App 的播放，早上给你一份小结")
                row("headphones", "Dyson Zone（可选）：空气、噪音、风扇、降噪")
            }.padding().glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                        .foregroundStyle(model.watchAppInstalled ? .green : .orange)
                    Text(model.watchAppInstalled ? "已检测到手表 App" : "还没检测到手表 App").font(.footnote)
                }
            }.padding().glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .onAppear { model.refreshWatchState() }
    }

    private var permissions: some View {
        pageView("lock.shield.fill", "需要的权限", "都只在本机使用，可以随时在设置里关闭。") {
            GlassGroup(spacing: 10) { VStack(spacing: 10) {
                permButton("heart.fill", "健康（心率、睡眠、环境声音）", "health") {
                    await model.requestHealthAuthorization(); return true
                }
                permButton("bell.badge.fill", "通知（早安小结、专注、提醒）", "notif") {
                    (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
                }
                permButton("music.note", "Apple Music 控制（可选）", "music") {
                    await model.requestMusicAuthorization(); return true
                }
                Text("蓝牙和定位会在你用到 Zone、通勤地图时再询问。").font(.caption).foregroundStyle(.white.opacity(0.6))
            } }
        }
    }

    private var zone: some View {
        pageView("headphones", "有 Dyson Zone 吗？", "可选。登录一次 MyDyson 账号取回蓝牙密钥，只存在本机钥匙串。") {
            VStack(alignment: .leading, spacing: 12) {
                row("xmark.app", "使用时请彻底退出 MyDyson：Zone 同一时间只接受一个控制端")
                row("questionmark.diamond", "标“未验证”的数据（空气/噪音布局、佩戴状态）是推断的，仅供参考")
                row("arrow.right.circle", "稍后在“Zone”标签里启用并登录")
            }.padding().glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        Label { Text(text).font(.subheadline) } icon: { Image(systemName: symbol).foregroundStyle(Palette.moon) }
    }

    private func permButton(_ symbol: String, _ title: String, _ key: String, _ ask: @escaping () async -> Bool) -> some View {
        Button {
            Task { if await ask() { granted.insert(key); Haptics.success() } }
        } label: {
            HStack {
                Image(systemName: symbol).frame(width: 28)
                Text(title).multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: granted.contains(key) ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(granted.contains(key) ? .green : .white.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding()
            .contentShape(Rectangle())
            .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
    }
}
