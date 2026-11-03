# SleepPause：在 Apple Watch 上检测入睡，自动暂停 iPhone 上的播放（适用于 Dyson Zone 等任意耳机）

AirPods Pro 2/3、AirPods 4 在 iOS 26 有“入睡时暂停媒体”功能，但这个功能不支持第三方耳机（例如 Dyson Zone）。
SleepPause 改用 **Apple Watch 判断你是否睡着**，再让 **iPhone 停止正在播放的音频**。暂停发生在 iPhone 上，所以不管用哪副耳机都有效。

## 工作原理

```
Apple Watch（整晚运行）                          iPhone
───────────────────────                          ──────────────────────────────
HKWorkoutSession(.mindAndBody) 保持后台运行
HKAnchoredObjectQuery 实时读取心率      ──┐
CMMotionManager 以 10Hz 读取手腕加速度      │
SleepOnsetDetector 每 30 秒判断一次：       │
 • 手腕连续静止 ≥ 12 分钟                   │
 • 且最近 5 分钟心率中位数                  │  WatchConnectivity
   ≤ 清醒基线 × (1 − 10%)                   │  sendMessage（会在后台唤醒 iPhone App）
   （基线取开始后前 5 分钟的中位数）        │  失败时改用 transferUserInfo
检测到入睡 → 发送 sleepOnset（不震动）   ──┘──▶ 抢占音频焦点 → 其他 App 收到打断后暂停
                                                  （也会直接暂停 Apple Music）
可选：检测到入睡后自动结束会话以省电              可选：把入睡时间写入“健康”App
```

**为什么用“抢占音频焦点”：** iOS 不允许第三方 App 直接暂停其他 App，也没有公开接口调节系统音量。
可行的办法是：本 App 启用一个不与其他声音混合的播放会话（`AVAudioSession .playback`，不带 `mixWithOthers`），系统会通知正在播放的 App（音乐、Spotify、播客、网易云、B站等）被打断，这些 App 通常会自动暂停。
随后本 App 释放音频会话，但不通知其他 App 恢复播放，所以音乐不会自动继续。

**为什么 iPhone 要“守候”：** iOS 规定，App 在后台只有本来就在播放声音时，才能重新启用音频会话。
因此点“开始今晚”后，iPhone App 会循环播放一段**完全无声、可与其他声音混合**的音频。你的音乐照常播放，不受影响。
检测到入睡时，再把这个会话切换成独占模式。

## 目录结构

```
SleepPause/
├── project.yml                    XcodeGen 配置（推荐用它重新生成工程）
├── SleepPause.xcodeproj           已在 Linux 上用 XcodeGen 生成好的工程，可直接打开
├── Shared/                        两端共用：SleepOnsetDetector（纯逻辑判定）、SleepMessage（消息格式）
├── Watch/                         watchOS App：SleepMonitor、WatchConnector、设置界面
├── iOS/                           iPhone App：MediaPauser、PhoneConnector、HealthWriter、日志界面
├── Tests/DetectorChecks.swift     判定逻辑测试（不依赖 Xcode，任何 Swift 环境都能运行）
└── scripts/
    ├── linux-check.sh             语法检查，并运行判定逻辑测试
    └── patch-watch-embed-plugins.sh  只有遇到 Xcode 26 的嵌入报错时才需要运行（见“常见问题”）
```

## 安装（需要 Mac + Xcode 26.1 或更高版本；iOS 27 手机建议用 Xcode 27；免费 Apple ID 即可）

1. 解压后，在终端进入 `SleepPause` 目录。
2. （推荐）重新生成工程：`brew install xcodegen && xcodegen`；也可以直接打开现成的 `SleepPause.xcodeproj`。
3. **修改 Bundle ID**：打开 `project.yml`，把 `BASE_BUNDLE_ID: com.example.sleeppause` 改成你自己的唯一 ID，例如 `com.zheng.sleeppause`，然后重新运行 `xcodegen`。
   如果你直接用现成工程：在 Xcode 里选中项目 → Build Settings → 搜索 `BASE_BUNDLE_ID` 修改。
4. Xcode → Settings → Accounts，登录你的 Apple ID。
5. 分别选中 **SleepPause** 和 **SleepPauseWatch** 两个 target → Signing & Capabilities：
   - Team 选择 “(你的名字) (Personal Team)”
   - 确认已勾选 **HealthKit**（entitlements 文件已经配好）
6. 手机通过数据线连接 Mac，并在 iPhone 上开启开发者模式：设置 → 隐私与安全性 → 开发者模式。手表也要开启开发者模式（手表上的 设置 → 隐私与安全性 → 开发者模式）。
7. 顶部 Scheme 选 **SleepPause**、设备选你的 iPhone，点 ▶︎ 运行。手表 App 会一起安装；如果没有自动装上，打开 iPhone 上的 Watch App → 找到 SleepPause → 点安装。
   也可以把 Scheme 切换成 **SleepPauseWatch**、设备选你的手表，直接安装到手表。
8. 第一次运行时：在 iPhone 上 设置 → 通用 → VPN与设备管理，信任你的开发者证书。
9. **免费 Apple ID 签名的 App 7 天后会失效**：到时连上 Mac，在 Xcode 里再点一次 ▶︎ 即可，数据不会丢失。

## 每晚的用法

1. 戴上 Apple Watch，用 Dyson Zone 开始播放音乐或播客。
2. 打开 iPhone 上的 SleepPause，点 **“开始今晚”**：
   - iPhone 进入守候状态（无声保活）；
   - 自动在手表上启动监测。如果手表没有反应，就在手表上打开 SleepPause，点“开始今晚监测”。
3. 前 5 分钟手表会采集你清醒时的心率作为基线，**这段时间请保持清醒**（看手机、听音乐都可以）。
4. 正常入睡即可。手表判定你睡着后，会通知 iPhone 暂停播放，全程不震动。
5. 默认情况下，检测到入睡 20 秒后手表会自动结束监测以节省电量。可以在手表的“阈值设置”里关闭这一项。

**第一次请先测试：**
- iPhone 上点“立即测试暂停”：Dyson Zone 里正在播放的音乐应该停止。
- 点“20 秒后测试”后立刻锁屏：用来验证锁屏、后台状态下也能暂停。
- 手表上点“测试暂停 iPhone 音乐”：验证手表 → iPhone 的整条链路。
- 每一步的结果都会记录在 iPhone 的“日志”里。

## 调整阈值（在手表 SleepPause 的“阈值设置”里修改，下次开始监测时生效）

| 参数 | 默认值 | 何时调整 |
|---|---|---|
| 静止时长 | 12 分钟 | 已经睡着但暂停太晚 → 调小（8–10 分钟）；还醒着就被暂停 → 调大（15–20 分钟） |
| 心率下降 | 10% | 你入睡后心率下降不明显 → 调成 5–7%；清醒躺着也被误判为睡着 → 调成 12–15% |
| 基线时长 | 5 分钟 | 开始监测时你已经很困 → 调短，或者早点点开始 |
| 动作阈值 | 0.020 g | 有轻微动作仍被当成静止 → 调小；呼吸或心跳的微动导致一直“不静止” → 调大 |
| 需要心率条件 | 开 | 心率读数不稳定时可以关闭，改为只按静止判断（误判会多一些） |
| 检测后结束会话 | 开 | 想整晚监测（耗电更多）时关闭 |

手表界面会实时显示：基线心率、当前心率、心率条件 ✓/✗、已静止分钟数 ✓/✗，方便你根据实际情况调整。

## 限制与注意事项

- **WatchConnectivity 后台唤醒不是 100% 可靠**：手表发出 `sendMessage` 会在后台唤醒 iPhone App，但需要 iPhone 在蓝牙或 Wi‑Fi 范围内。
  如果 iPhone 此时不可达，消息会改用 `transferUserInfo` 排队发送，可能会延迟送达，那样就起不到暂停的作用了。
  另外，如果你在多任务界面上划掉 SleepPause，iOS 可能不会再在后台唤醒它，所以睡前请不要划掉。
- **能否暂停取决于播放 App 是否遵守系统的音频打断**：Apple Music、播客、Spotify 和大多数音乐、视频 App 都会暂停；个别 App 可能不响应，或者过一会儿又自己恢复播放。
- **无法调节系统音量**：iOS 没有公开接口，所以做不到 AirPods 那样的“渐弱”效果，只能直接停止。
- **耗电**：手表整晚运行 HKWorkoutSession，并以 10Hz 读取加速度，一夜大约耗电 15–30%（因机型而异）；建议开启“检测后结束会话”。iPhone 无声保活耗电很少。
- **准确度**：只靠“静止 + 心率下降”做判断，比 AirPods 或 Apple 官方的睡眠追踪粗糙。“清醒但静止躺着、心率又偏低”时可能误判，请按上表调整。
- 监测期间，“健康”App 里可能会短暂出现一条“身心”体能训练；结束时本 App 会丢弃这条记录（`discardWorkout`），不会保存到健康数据。
- **Dyson Zone 只用来播放**：它的蓝牙协议不提供原始的运动数据，所以没有用 Zone 来检测睡眠。Zone 自带的“摘下耳机自动暂停”功能照常有效。

## Dyson Zone 扩展模块（可选，非官方）

在 iPhone 的 “Zone” 标签页里打开 **启用 Dyson Zone 模块**。不打开时，App 的行为和原来完全一样。
协议实现（握手、加密、分帧、云端取 LTK）改写自 [nikships/dyson-zone-companion](https://github.com/nikships/dyson-zone-companion)（MIT）。
字段含义来自对 MyDyson Android 6.4.26420 的静态分析。

> **状态说明**：下表的“已验证”是指在 Linux 上通过了单元测试或语法检查。**所有 Zone 功能都还没有在真机上测试过。**
> 标 ⚠️ 的是推断出来的，用 ZoneProbe 抓包确认之后，只需要改一处代码。

### 新增安装步骤

1. 用 Mac 重新打开 `SleepPause.xcodeproj`（或执行 `xcodegen generate` 重新生成），装到 iPhone 上。
   - 不需要新增 capability。
   - 新增的后台模式（bluetooth-central、location）和权限说明已经写在 `iOS/Info.plist` 里。
2. 在 iPhone 上打开 Zone 标签 → **登录 Dyson 账号**：
   1. 输入邮箱，收取验证码。
   2. 输入验证码和密码。
   3. 选择你的 Zone。

   App 会取回蓝牙密钥（LTK），存进本机钥匙串（只存在这台设备上）。
   - 密码只发给 Dyson，不会保存。
   - 账号信息只在手机上输入，项目里不包含任何凭据。
   - 中国区账号如果登录失败，可以在登录页修改“服务器”字段。⚠️ 中国区服务器地址未验证。
3. **彻底退出 MyDyson**（上滑关闭；如果仍连不上，就关掉它的蓝牙权限）。Zone 同一时间只接受一个控制端。
4. 按提示允许蓝牙、通知（噪音提醒）、定位（只有通勤地图会用到）和“健康”写入（环境声音）。

### 1. 入睡联动
手表判定你入睡后，iPhone 先暂停音乐（原有功能），然后：
- **风扇关**：写 2DD12001 = 0，并先把自动模式 2002 设为 0。
- **降噪保持不变**：默认不关降噪，睡着后继续隔绝噪音。
  - 如果你确实想入睡时关降噪，可以手动打开“入睡时关闭降噪”（把属性 0x400A 设为 3），默认关闭。
- 同时暂停自动降噪切换（见第 5 节），保持当前模式过夜。

“关风扇”默认开启。Zone 没有连接时会跳过，并记入日志，不会影响暂停音乐。
页面里有“测试”按钮可以立即试一次。⚠️ 戴面罩时写风扇的效果没有实测过。

### 2. 快捷指令 / Siri
提供 5 个动作：
- 获取 Zone 电量
- 获取 Zone 噪音和空气读数
- 设置 Zone 降噪模式
- 设置 Zone 风扇档位（0–3）
- 开始今晚的入睡监测（会打开 App）

在“快捷指令”App 里搜索 SleepPause 就能找到。Zone 相关的动作需要手机已经连上 Zone，最多等待约 12 秒。

### 3. 噪音暴露 →“健康”
- Zone 的环境声压按 1 分钟算出 Leq，写入“健康”的 **环境声音**（environmentalAudioExposure）。
  - 苹果允许第三方 App 写入这种数量样本，但“噪音通知事件”只能读、不能写。
  - 因此“超标提醒”由本 App 自己发本地通知。
- 写入失败时，数据只保存在本机。
- 当日剂量按 85 dB·8 小时、3 dB 交换率计算，达到 100% 时通知一次。
- 只统计佩戴期间的数据（前提是能读到佩戴状态）。
- ⚠️ 数据来自 2DD1201D，**字段布局是推断的（界面上标着“未验证布局”）**。也不确定这个数值是不是 A 计权。
- 每一帧的原始字节都记录在 `zone-aq-raw.jsonl`，可以用“导出原始 201D 记录”导出，布局确认后能重新解析。
- 布局只需在 `iOS/Zone/Core/ZoneAQDecoder.swift` 的 `ZoneAQLayout.current` 一处修改。

### 4. 通勤污染地图
只有打开“通勤记录”时才会使用定位（后台记录时，状态栏会显示蓝色定位指示）。
- 每 10 秒左右，把 NO₂、VOC 和噪音读数与当前位置一起保存到本机 `commutes.json`。
- 地图上用彩色路线和圆点热区显示：绿 / 黄 / 橙 / 红。
- 下方列表对比每条路线的用时、距离、平均值、最高值和“偏高占比”。
- 颜色分档是经验值，不是官方 AQI。⚠️ 读数依赖同一个未验证的布局。

### 5. DIY 自适应降噪
- 环境噪音 ≥ 嘈杂阈值（默认 70 dB）时切到 **降噪**。
- 低于安静阈值（默认 58 dB）时切到 **通透**（也可以选对话或关闭）。
- 两个阈值之间是迟滞区，保持当前模式。
- 判断时取 20 秒中位数；每次切换后至少保持 60 秒。
- 你手动切换（在 App、Zone 按键或快捷指令里）之后，自动切换暂停 30 分钟。时长可以调，也可以一键恢复。
- **睡眠期间不切换**：今晚监测进行中（iPhone 守候），以及检测到入睡后 12 小时内，自动切换完全暂停，保持当前降噪模式，不会因为夜里安静而切到通透或关闭。
  - 早上可以在 Zone 页点“醒了，恢复自动切换”。

### 佩戴检测（⚠️ 未验证）
- 读取特征 2DD12004（MyDyson 里叫“当前佩戴状态”）。
- 打开“摘下耳机时停止今晚监测”后：守候期间摘下 Zone 超过 60 秒，就会自动停止今晚的监测。
- 默认关闭。请先在 Zone 标签里确认“佩戴”状态会随摘戴变化，再打开。

### 后台蓝牙
- 使用 bluetooth-central 后台模式和 CoreBluetooth 状态恢复，断开后会自动重新连接。
- 如果 App 被你手动上滑关掉，iOS 不会在后台重新启动它，需要再打开一次。

### 相关代码
- `iOS/Zone/Core`：纯逻辑，在 Linux 上做了单元测试。包括分帧、201D 解码、迟滞控制、噪音剂量和通勤统计。
- `iOS/Zone/Core` 里还新增了：污染加速、番茄钟、电量提醒和周报的纯逻辑（Linux 单元测试）。
- `iOS/Zone/Extras`、`Widgets`、`WidgetShared`：专注、实时活动、小组件，以及共享快照（快照逻辑做了单元测试，其余只做了语法检查）。
- `iOS/Zone/BLE`：加密、云端登录、钥匙串、蓝牙连接管理。只做了语法检查。
- `iOS/Zone/Features`（含快捷指令 ZoneIntents.swift）和 `iOS/Zone/Views`：“健康”写入、通勤记录、快捷指令和界面。只做了语法检查。

## 更多功能（第 6 阶段，根据网上的需求调研添加）

> 和上面一样：**还没有在 Xcode 里编译过，也没有在真机上测试过。**纯逻辑部分已经在 Linux 上通过了单元测试。
> 标 ⚠️ 的功能依赖未验证的 Zone 字段：佩戴 2004、空气/噪音 201D 推断布局。数据缺失时会显示“–”或者不动作，不会报错。

### A. 锁屏 / 主屏幕小组件
参考 [Paku](https://apps.apple.com/us/app/paku-air-quality-aqi-map/id1534130193) 和 [CAPod](https://github.com/d4rken-org/capod) 的小组件。
- 显示电量、降噪模式、空气等级（取 NO₂/VOC 中较差的一项）、环境噪音和今日噪音剂量。
- 支持这几种尺寸：主屏幕小号/中号；锁屏的圆形（电量）、矩形和单行。
- 添加方法：长按主屏幕或锁屏 → 添加小组件 → SleepPause。
- ⚠️ 空气和噪音来自 201D。没有读数时显示“–”，电量照常显示。

### B. 实时活动 / 灵动岛
参考 [Paku](https://mwm.ai/apps/paku-for-purpleair/1534130193) 和 [SoundGuard](https://soundguard.app/)。
- 在锁屏和灵动岛上实时显示空气等级、环境噪音、电量；专注时还会显示倒计时。
- 开启方法：Zone 页 →“在锁屏和灵动岛显示空气与噪音”。开始专注时也可以自动开启。
- 灵动岛需要 iPhone 14 Pro 或更新的机型，其他 iPhone 只在锁屏显示。
- ⚠️ 空气和噪音来自 201D。

### C. 污染时自动加大风扇
参考 Home Assistant 的 [VOC 超阈值触发](https://www.home-assistant.io/triggers/air_quality.voc_crossed_threshold/) + [提高风扇转速](https://www.home-assistant.io/actions/fan.increase_speed/)。Dyson 设计师的 [Zone 新 App 方案](https://www.romaricdelahaie.com/portfolio/dyson-headphone-app-design) 也提出过“根据污染自动调风量”。
- 触发：NO₂ ≥ 53 ppb 或 VOC ≥ 500 ppb，持续 20 秒，就把风扇调到中度（可以设成轻度）。
- 恢复：空气恢复 20 秒、且已经加速至少 2 分钟后，调回原来的档位。恢复后冷却 5 分钟才会再次加速。
- 不会动作的情况：
  - 你手动调了风扇（以你的设置为准）。
  - 面罩没装上（2005）。
  - 睡眠监测期间或入睡后。
  - 没有读数。
- **它不会改降噪。**默认关闭，在 Zone 页“污染加速”里打开。
- ⚠️ 依赖 201D。

### D. 专注番茄钟
参考 [Pomodoro + 快捷指令](https://www.bulbapp.com/u/pomodoro-apple-shortcuts) 和 [Pomotto](https://pomotto.app/)，以及 AirPods 的“专注时自动降噪”快捷指令玩法。
- 新增“专注”标签页。默认专注 25 分钟、短休息 5 分钟，每 4 个番茄长休息 15 分钟。
- 专注时切到降噪，休息时切到通透（都可以改）。专注时可以指定风扇档位。
- 每个阶段结束时发通知；专注期间暂停自适应降噪。
- ⚠️ “摘下耳机自动暂停计时”依赖 2004。读不到佩戴状态时，计时照常进行。
- 睡眠监测期间不能开始专注；开始“今晚监测”会自动结束专注，降噪交给睡眠逻辑（保持开启）。
- 快捷指令里可以用“开始 Zone 专注”和“结束 Zone 专注”，再配合系统专注模式的自动化。

### E. 每周报告
参考 [bloop](https://www.bloopy.tech/) 和 [DeciBar](https://github.com/gostonx/DeciBar) 的每周声音剂量洞察。
- 每周一 9:00 之后（北京时间，按手机时区计算），App 下次在前台或后台运行时，推送上周的报告：
  - 每日噪音剂量、最吵的一天、≥85 dB 的分钟数
  - 通勤次数、平均 NO₂、最干净的路线
  - 专注次数和分钟数
  - 入睡次数和中位入睡时间
- 也可以在 Zone 页点“查看上周报告”。
- ⚠️ 噪音和空气部分依赖 201D，报告里会注明；睡眠和专注部分不依赖。

### F. 低电量与睡前电量提醒
参考 [MagicPods](https://github.com/steam3d/MagicPods-Windows) 的低电量通知。
- Zone 电量降到 20% 和 10% 时各通知一次，充电后重新生效。
- 点“开始今晚”时如果电量低于 30%，会提醒你充电。入睡判定和暂停音乐不受影响。
- 电量来自 201E（dyson-zone-companion 在真机上读过），不依赖未验证字段。

### G. Siri：“空气怎么样”
参考 [Paku](https://apps.apple.com/us/app/paku-air-quality-aqi-map/id1534130193) 的“问 Siri 附近空气”。
- 说“SleepPause 空气怎么样”，Siri 会用一句话回答空气、噪音和电量。
- 没连上 Zone 时，会说出最后一次读数和它的时间。
- ⚠️ 依赖 201D。

### 这些功能的安装变化
1. 项目新增了 **SleepPauseWidgets** 小组件扩展 target（已写进 project.yml）。用 Xcode 打开后：
   - 给这个 target 也选上你的 Team。
   - 它的 Bundle ID 会自动变成 `$(BASE_BUNDLE_ID).widgets`。
2. App 和小组件共用一个 **App Group**：`group.$(BASE_BUNDLE_ID)`。改了 BASE_BUNDLE_ID，它会跟着变，不用单独改。
   - 如果 Xcode 提示 App Group 无法注册（部分免费账号会遇到），可以删掉两个 entitlements 文件里的 App Group。
   - 这样小组件会一直显示“打开 App 连接 Zone”，实时活动、专注、提醒、周报不受影响。
3. 第一次使用时允许通知（专注、电量、污染、周报都会用到）。
4. 如果锁屏看不到实时活动：到“设置 → SleepPause”里打开“实时活动”。

## 设计升级与新功能（第 7 阶段）

> 依然**没有在 Xcode 里编译过，也没有在真机上测试过**。纯逻辑部分在 Linux 上通过了单元测试，其余代码只做了语法检查。
> 设计示意图在 `docs/previews/`（PNG）。**这些是用 HTML 画的示意图，不是 App 截图。**

### 设计
- **统一的视觉风格**（`iOS/Design/Theme.swift`、`WidgetShared/LevelPalette.swift`）：
  - 睡眠相关用夜空蓝紫渐变。
  - 空气/噪音等级用绿 → 黄 → 橙 → 红，App、小组件、实时活动、通勤地图用同一套颜色。
  - 圆角卡片、状态胶囊、SF Symbols 动画（pulse / bounce / variableColor / replace）。
  - 支持深色模式和动态字体。开启“减弱动态效果”时，呼吸动画会停止。
- **睡眠页**：
  - 夜空主卡片（守候中时月亮会缓慢闪动）。
  - 早安小结卡片、助眠声音卡片。
  - 连续天数条，点开可以看成就墙。
- **Zone 首页**：
  - “呼吸光球”：空气等级，颜色和呼吸动画。
  - 动画圆环：今日噪音剂量。
  - 状态胶囊：电量、降噪、风扇、佩戴。
  - 未验证的数据统一用橙色“未验证”标记。
  - 空状态：未启用、需要登录。错误状态：蓝牙关闭、被 MyDyson 占用、连接失败（带“重试”）。
  - 支持下拉刷新重连。
- **首次启动引导**：4 页，分别介绍：
  - App 做什么。
  - 怎么在 Xcode 里选 Team、装到手表。
  - 一键请求权限（健康、通知、Apple Music）。
  - Zone 的注意事项。
  - 以后不会再弹出。
- **触感反馈**：开始/停止守候、切换降噪和风扇、番茄钟换阶段、解锁成就、引导页翻页。
- **小组件 / 实时活动**：
  - 背景渐变随空气等级变化；文字为深色优先。
  - 小号小组件适合 StandBy 床头模式（充电时横放）。
- **Apple Watch**：
  - 新的睡前界面：暗色渐变；静止圆环随静止分钟填满；心率条上的白线是入睡目标心率（基线 ×（1 − 下降%））。
  - 动/静图标会实时切换。
  - 新增**表盘复杂功能**（圆形、矩形、单行、角落）：显示监测状态和下一次智能闹钟时间，点按打开 App。

### 新功能
1. **手表智能闹钟**
   - 设定时间和窗口（默认 30 分钟）。窗口内检测到持续活动（约 1.5 分钟，单次翻身不算）就用轻柔震动叫醒你，最晚在设定时间叫醒。
   - 窗口内可以每 5 分钟轻拍一次，帮你从深睡浮上来。
   - 打开后，手表监测会持续整晚，更耗电。
   - 参考：[Remwake](https://thejamiefarrell.com/remwake.html)、[AutoWake / AutoSleep](https://autowake.tantsissa.com/how-it-works)、[SleepPhaseWakeApp](https://github.com/rusel95/SleepPhaseWakeApp)。
   - 只用手表加速度计，不依赖 Zone。⚠️ 后台持续震动需要真机验证。
2. **助眠声音**
   - 在 iPhone 上实时生成棕/粉/白噪音（不循环），通过 Zone 播放，**降噪保持开启**。
   - 手表检测到入睡后，按设定时间（默认 90 秒）平滑淡出；音乐暂停照常进行。
   - 也可以设成“没检测到入睡时 30/60/90 分钟后淡出”。
   - 参考：[Rest Easy](https://apps.apple.com/tm/app/rest-easy-sleep-timer/id6759265417)、[Veil](https://www.veilsleep.app/brown-noise-app)、[Noise Machine](https://apps.apple.com/us/app/noise-machine-brown-white/id1261956119)。不依赖 Zone 数据。
3. **早安小结**
   - 早上（智能闹钟叫醒，或手表结束监测时）推送并在睡眠页显示：
     - 入睡用时（从开始监测到检测入睡）
     - 睡眠时长
     - 智能闹钟提前了几分钟
     - 夜间环境噪音（平均、最高、≥55 dB 的分钟数）
   - 参考：[Sleep Cycle“Asleep after”](https://sleepcycle.com/sleep-talk/statistics)、[Pillow 环境噪音](https://intercom.help/pillow_app/en/articles/7945541-what-s-included-in-pillow-premium)。
   - ⚠️ 夜间噪音来自 201D（未验证），只有整夜连接并佩戴 Zone 时才有；没有时会写“没有夜间噪音数据”。
4. **连续天数与成就**
   - 三条连续记录：
     - 守护睡眠：检测到入睡
     - 专注：当天专注 ≥25 分钟
     - 安静日：戴 Zone ≥1 小时且噪音剂量 <50%
   - 9 个徽章：第一晚、七夜守护、早睡达人、十番茄、清新通勤等。解锁时发通知并有触感反馈。
   - 参考：[Streaks](https://streaks.app/)、[Forest](https://apps.apple.com/us/app/forest-focus-for-productivity/id866450515)、[HabitStreak](https://habitstreak.me/)。
   - ⚠️ “安静日 / 安静一周 / 清新通勤”依赖 201D，读不到时只是不会解锁。

### 新增安装步骤
- 项目里多了一个 target：**SleepPauseComplications**（手表表盘复杂功能），共 4 个 target。在 Xcode 的 Signing 里给它也选上你的 Team。
  - Bundle ID 自动设为 `$(BASE_BUNDLE_ID).watchkitapp.complications`。
- 手表 App 和复杂功能也使用同一个 App Group `group.$(BASE_BUNDLE_ID)`。
  - 免费账号如果注册不了，可以删掉手表的两个 entitlements 里的 App Group：复杂功能会一直显示“未开始”，其他功能不受影响。
- 智能闹钟在手表 App 首页 →“智能闹钟”里设置。表盘复杂功能在手表上长按表盘 → 编辑 → 选择 SleepPause。

## 液态玻璃（Liquid Glass）界面（第 8 阶段，按 iOS 27 / watchOS 27 调整）

> 下面的效果图都是**示意图（mockup）**，不是真机截图：`docs/previews/06-glass-zone.png`、`07-glass-sleep-focus.png`、`08-glass-ios27-settings.png`。

### 用到的系统 API（都已在 Apple 当前文档核对过名字和可用版本）
| 位置 | API | 最低系统 |
|---|---|---|
| 卡片、标签、圆形按钮 | `View.glassEffect(_:in:)`，`Glass.regular / .clear`，`.tint(_:)`，`.interactive()` | iOS 26 / watchOS 26 |
| 相邻玻璃放在一起采样、互相融合 | `GlassEffectContainer(spacing:)` | iOS 26 |
| “开始专注”分裂成“暂停 + 结束”、Zone 标签展开成档位按钮 | `glassEffectID(_:in:)` + `@Namespace` | iOS 26 |
| 主按钮 / 次按钮 | `.buttonStyle(.glassProminent)` / `.buttonStyle(.glass)` | iOS 26 / watchOS 26 |
| 底部“正在运行”条（守候中 / 专注倒计时 / 助眠声音） | `tabViewBottomAccessory(isEnabled:content:)`，`tabViewBottomAccessoryPlacement` | iOS 26.1 |
| 下滑时标签栏缩小 | `tabBarMinimizeBehavior(.onScrollDown)` | iOS 26 |
| 下滑时导航栏缩小（**iOS 27 新增**） | `toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)` | iOS 27 |
| 无障碍“显示边框”时给自绘玻璃加描边 | `EnvironmentValues.accessibilityShowBorders` | 用 26.1+ SDK 编译 |
| 主屏幕“清透 / 着色”外观下的小组件 | `widgetRenderingMode`、`widgetAccentable()` | iOS 16+ |

### 设计规则
- **玻璃只用在“功能层”**：按钮、标签、浮在地图上的控件、底部状态条。内容本身（空气渐变卡、入睡卡、地图）是不透明的鲜艳底色，玻璃浮在上面才好看。
- **只有主操作和空气等级会着色**（“开始今晚”、“开始专注”、当前降噪/风扇档）；其他玻璃都是无色的，颜色只放在图标上。
- 标签栏、导航栏、工具栏、表单控件全部用系统自带样式，没有自定义背景，iOS 27 的新玻璃外观会自动生效。
- 每个标签页背后有一层淡淡的颜色（睡眠：靛蓝，Zone：随空气等级变色，专注：橙色），让玻璃有东西可以折射；下半部分回到系统分组背景，浅色 / 深色模式都清楚。

### 无障碍和旧系统
- **减少透明度**：自绘玻璃变成不透明的系统背景色（`accessibilityReduceTransparency`）。
- **增强对比度 / 显示边框**：自绘玻璃加 1.5 pt 描边。
- **减弱动态效果**：呼吸光球不再呼吸（原有逻辑）。
- **iOS 17–25 / watchOS 10–25**：所有玻璃 API 都包在 `if #available` 里，旧系统退回到原来的半透明材质和 `bordered` 按钮样式，功能不变。

### iOS 27 有什么不同
- **自动生效、不需要改代码**：iOS 27 的玻璃更不透明一些、边缘更深，并跟随用户在“设置 → 外观”里的**液态玻璃滑杆**（从“清透”到“着色”）。我们的自绘玻璃用的是同一个系统材质，所以也会跟着变。两端都看过示意，文字仍清楚。
- **只在 iOS 27 上才有的代码**：导航栏下滑缩小（`toolbarMinimizationBehavior`）。它用 `#if compiler(>=6.4)`（Xcode 27 自带 Swift 6.4）加 `if #available(iOS 27.0, *)` 双重保护：用 Xcode 26 编译时自动跳过，不会报错。
- **考虑过但没用**：iOS 27 的 `TabRole.prominent`（把一个标签单独放到标签栏右侧）——适合“购物车 / 搜索”这类动作型标签，我们四个标签地位相同，所以不用。

### 安装变化
- 最低需要 **Xcode 26.1**（`tabViewBottomAccessory(isEnabled:)`、`accessibilityShowBorders` 需要 26.1 SDK）。
- 手机是 iOS 27：**建议用 Xcode 27**（Apple 说明 Xcode 27 支持 iOS 17+ / watchOS 10+ 真机调试，并包含 iOS 27 SDK）。
- 最低系统版本不变：iOS 17 / watchOS 10。没有新增文件、权限或 target，`project.yml` 不需要改。

### 未能确认的地方（没有 Mac / 真机，只在 Linux 上做了语法检查）
- 实际渲染效果：效果图是示意，不是 iOS 27 模拟器截图；玻璃的真实折射、滑杆两端的样子需要在真机上看。
- 卡片里放玻璃标签、`GlassEffectContainer` 嵌套在 `List` 行里的表现，以及 `.glassEffectID` 在 `Form` 里的变形动画是否流畅。
- `#if compiler(>=6.4)` 依据的是 Xcode 27 发布说明里的 “includes Swift 6.4”。

## 在 GitHub Actions 上编译（没有 Mac 时）

仓库根目录的 `.github/workflows/build.yml` 会在 `xcode-27` runner 上选择已安装的最新 Xcode（优先 27.x），用 XcodeGen 重新生成工程，然后：

- 运行 `scripts/linux-check.sh` 里的逻辑测试（工程里没有 XCTest target）
- 为通用 iOS 模拟器和通用 iOS 设备编译 SleepPause（包含小组件和手表 App；设备构建设置 `CODE_SIGNING_ALLOWED=NO`）
- 为 watchOS 模拟器编译 SleepPauseWatch
- 成功后额外打一个未签名的 `.ipa` / `.xcarchive`（构建产物，不是签名包）

`BASE_BUNDLE_ID` 保持占位符 `com.example.sleeppause`，需要你自己改成唯一 ID。未签名的 ipa 可以用 Sideloadly / AltStore 再签名，但**手表 App 不能靠这种方式装到手表上**。

## 常见问题

- **Xcode 26 安装时报 “...must be embedded in the parent app bundle's PlugIns directory”**：运行 `./scripts/patch-watch-embed-plugins.sh` 后重新构建（参考 XcodeGen issue #1613）。
- **手表上没有出现 App**：打开 iPhone 上的 Watch App → 往下找到 SleepPause → 点安装；或者直接把 Scheme 切换成 SleepPauseWatch，安装到手表。
- **点“开始今晚”后手表没启动**：直接在手表上手动点“开始今晚监测”，效果相同。
- **Zone 一直显示“正在寻找”或“被其他设备控制”**：先彻底退出 MyDyson；再把 Zone 关机重开；仍然不行就在“设置 → 蓝牙”里忽略 Zone 后重试。
- **签名时提示 HealthKit 不可用**：确认两个 target 都已添加 HealthKit capability，并且 Bundle ID 已改成你自己唯一的 ID。

## 致谢

Dyson Zone 协议部分改写自 [nikships/dyson-zone-companion](https://github.com/nikships/dyson-zone-companion)（MIT），文件头部保留了出处。

思路参考了 [mako9/auto-stop](https://github.com/mako9/auto-stop)（MIT 许可）：手表 → WatchConnectivity → iPhone 抢占 AVAudioSession。
本项目的代码是重新编写的，改为实时使用“心率 + 动作”判定，而不是轮询 HealthKit 里的睡眠记录。
原因是 Apple Watch 的睡眠记录通常要到醒来后才会写入，不适合用来实时判断刚刚入睡。
