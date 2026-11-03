# SleepPause visual system

SleepPause follows Apple’s first-party apps on iOS 27 and watchOS 27. Color, type, lists, and materials come from the system. Liquid Glass stays where the system already uses it: the tab bar, navigation bars, toolbars, sheets, and the prominent action buttons. Content sits on `Color(.systemGroupedBackground)` and `.secondarySystemGroupedBackground`. There is no custom paper palette and no geometric status shapes.

Mockups, each labelled as a mockup and not a device screenshot:

- `docs/previews/01-sleep-tab.png`
- `docs/previews/02-zone-dashboard.png`
- `docs/previews/03-onboarding.png`
- `docs/previews/04-watch.png`
- `docs/previews/05-widgets.png`
- `docs/previews/06-glass-zone.png`
- `docs/previews/07-glass-sleep-focus.png`
- `docs/previews/08-glass-ios27-settings.png`

## What it follows

| App | What SleepPause takes from it |
|---|---|
| Health | Inset grouped summary rows: a tinted SF Symbol and category title, a large rounded number with its unit, and a caption. Trends use Swift Charts. |
| Fitness | Rounded numerals. The watch face is black with a full-screen page and one large primary button. |
| Health Sleep and Clock alarms | Sleep uses indigo, `bed.double` and `moon.zzz`. The sleep tab is the system dark appearance, dimmed slightly with `.brightness` while a night is armed. |
| Weather | The Zone home is a summary module on the grouped background. The map uses a full-bleed `Map` with a floating control. |
| Clock and Apple Music | The focus timer is a large rounded countdown. Its primary button is system orange. |
| Noise and Hearing | Decibels use a rounded number, and the caption says 正常 or 偏响 (under 80 dB, or at and above). |

## Color

Semantic colors only. `Palette` and `Night` in `iOS/Design/Theme.swift` are aliases for these system colors. `LevelPalette` does not store hex values.

| Role | System color |
|---|---|
| Page background | `Color(.systemGroupedBackground)` |
| Cards | The inset grouped list row (`.secondarySystemGroupedBackground`) |
| Primary / secondary text | `.primary`, `.secondary` |
| Sleep | `.indigo` |
| Air | `.teal` |
| Focus timer | `.orange` |
| Levels 好 / 一般 / 偏高 / 差 | `.green`, `.yellow`, `.orange`, `.red` |
| Headphone playback on the noise chart | `.orange` |
| Zone ambient on the noise chart | `.teal` |
| Watch environmental on the noise chart | `.indigo` |
| Stop / destructive | `.red` |
| Unverified data | `.orange` with `questionmark.circle` |

A level is never color alone. `LevelMark` shows the Health-style SF Symbol and the word 好, 一般, 偏高, or 差. The Noise-style caption adds 正常 or 偏响 next to the decibel number. Widgets in the accented rendering mode switch to `chart.bar.fill` with a variable value so the level still reads when the system strips color.

## Type and layout

SF Pro through the standard text styles: `.largeTitle`, `.headline`, `.subheadline`, `.caption`. Key numbers use `.system(_:design: .rounded)` so they match Fitness and Health and still scale with Dynamic Type. Numbers set `minimumScaleFactor` and stay on one line.

Screens are `List` or `Form` with `.insetGrouped` and a large navigation title, the same structure as Health and Settings. A summary row is a tinted symbol, a category title, the big number, and a caption. Swift Charts draws the noise trend, recent sleep-onset times, and the weekly dose bars.

## Liquid Glass

The tab bar uses the system bar, including `tabBarMinimizeBehavior(.onScrollDown)` and the bottom accessory on iOS 26. Navigation bars can shrink with `toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)` when the iOS 27 SDK is present. Prominent actions use `.glassProminent` (or `.borderedProminent` before iOS 26): start tonight, the focus timer, onboarding continue, and the Zone ANC and fan choices. Sheets are system sheets.

`Reduce Transparency` replaces custom glass with `.secondarySystemBackground`. `Increase Contrast` and `Show Borders` add a 1.5 pt stroke on that glass. List and form content is not wrapped in glass cards.

## Sleep

The sleep tab and the achievements sheet use `.preferredColorScheme(.dark)` and an indigo tint, with `bed.double.fill` and `moon.zzz.fill`. While tonight is armed, the view’s brightness is reduced by 0.08 so the page is dimmer without a separate color set. The single primary button stays in the bottom safe area: indigo to start, red to stop. The watch uses a full-screen `.containerBackground` gradient from `.indigo` to `.black`, the same idea as the Sleep and Workout apps, and complications use `AccessoryWidgetBackground` plus the system accessory families.

## Ergonomics

- iPhone controls are at least 44 pt tall. Watch primary buttons are at least 44 pt tall.
- One primary action per screen, in the bottom thumb zone: “开始今晚”, “开始专注” / “暂停”, “继续” on onboarding, “开始今晚监测” and “我醒了” on the watch.
- Destructive actions stay separate: “停止守候” is red, “结束” on the focus screen is a bordered destructive button above the orange primary, and “停止监测” sits alone at the bottom of the watch bedtime page.
- Bedtime haptics are a soft impact. The watch alarm still repeats with a light tap rather than a full notification buzz.
- Reduce Motion turns off the armed-state animation on the sleep tab.
