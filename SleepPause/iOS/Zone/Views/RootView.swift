import SwiftUI

struct RootView: View {
    @AppStorage("onboarding.done") private var onboardingDone = false
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var headphones = HeadphoneSettings.shared
    @ObservedObject private var focus = FocusManager.shared
    @ObservedObject private var sounds = SleepSoundPlayer.shared

    /// Show the bottom accessory only while something is actually running.
    private var hasLiveStatus: Bool { model.isArmed || focus.session.isActive || sounds.isPlaying }

    var body: some View {
        TabView {
            ContentView().tabItem { Label("睡眠", systemImage: "moon.zzz") }
            if headphones.usesZone {
                ZoneView().tabItem { Label("Zone", systemImage: "headphones") }
            }
            FocusView().tabItem { Label("专注", systemImage: "timer") }
            if headphones.usesZone {
                CommuteMapView().tabItem { Label("通勤地图", systemImage: "map") }
            }
        }
        // No custom tab-bar background: the system Liquid Glass bar is used as-is.
        .tint(Palette.blue)
        .modifier(GlassTabChrome(enabled: hasLiveStatus))
        .fullScreenCover(isPresented: Binding(get: { !onboardingDone }, set: { onboardingDone = !$0 })) {
            OnboardingView().environmentObject(AppModel.shared)
        }
    }
}

/// iOS 26+: the tab bar shrinks on scroll and a glass "now running" accessory sits above it.
/// - `tabBarMinimizeBehavior(_:)`         iOS 26.0  https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)
/// - `tabViewBottomAccessory(isEnabled:)` iOS 26.1  https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)
private struct GlassTabChrome: ViewModifier {
    var enabled: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory(isEnabled: enabled) { NowRunningAccessory() }
        } else if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

/// Bottom accessory: tonight's watch / focus timer / sleep sounds, with one action.
@available(iOS 26.0, *)
struct NowRunningAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var focus = FocusManager.shared
    @ObservedObject private var sounds = SleepSoundPlayer.shared

    var body: some View {
        HStack(spacing: 10) {
            if focus.session.isActive {
                Image(systemName: "timer").foregroundStyle(Palette.blue)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let rem = Int(focus.session.remaining(at: ctx.date))
                    Text("\(focus.session.phase.label) \(String(format: "%02d:%02d", rem / 60, rem % 60))")
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { focus.togglePause(); Haptics.tap() } label: {
                    Image(systemName: focus.session.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(focus.session.isPaused ? "继续专注" : "暂停专注")
            } else if model.isArmed {
                Image(systemName: "moon.zzz.fill").foregroundStyle(Palette.red)
                Text(placement == .inline ? "守候中" : "守候中 · 降噪保持开启")
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if sounds.isPlaying, placement != .inline {
                    Image(systemName: sounds.color.symbol).foregroundStyle(Palette.secondaryInk)
                }
                Button { model.stopTonight(); Haptics.night() } label: {
                    Image(systemName: "stop.fill").frame(width: 44, height: 44)
                }
                .accessibilityLabel("停止守候")
            } else if sounds.isPlaying {
                    Image(systemName: sounds.color.symbol).foregroundStyle(Palette.blue)
                Text(sounds.isFading ? "正在淡出…" : sounds.color.label)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button { sounds.fadeOutAndStop(seconds: 3); Haptics.night() } label: {
                    Image(systemName: "pause.fill").frame(width: 44, height: 44)
                }
                .accessibilityLabel("停止助眠声音")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 16)
    }
}

// MARK: - iOS 27 additions (compiled only with the iOS 27 SDK, i.e. Xcode 27 / Swift 6.4+)

extension View {
    /// iOS 27: the large navigation bar shrinks away while scrolling long lists.
    /// `toolbarMinimizationBehavior(_:for:)` — iOS 27.0, supported placement `.navigationBar`.
    /// https://developer.apple.com/documentation/swiftui/view/toolbarminimizationbehavior(_:for:)
    @ViewBuilder
    func minimizingNavigationBar() -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
