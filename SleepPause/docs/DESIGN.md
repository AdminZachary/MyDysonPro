# SleepPause visual system

Bauhaus-inspired and built for reading at night. Content is flat. Liquid Glass stays on controls and on the system tab bar and navigation bar. Behaviour (ANC held through sleep, no calibration writes) is unchanged.

Mockups, each labelled as a mockup and not a device screenshot:

- `docs/previews/01-sleep-tab.png`
- `docs/previews/02-zone-dashboard.png`
- `docs/previews/03-onboarding.png`
- `docs/previews/04-watch.png`
- `docs/previews/05-widgets.png`
- `docs/previews/06-glass-zone.png`
- `docs/previews/07-glass-sleep-focus.png`
- `docs/previews/08-glass-ios27-settings.png`

## Palette

Daytime screens follow the system light or dark appearance. Bedtime screens (iPhone sleep tab, achievements opened from it, the watch app) always use the night column.

| Token | Light | Dark | Night (fixed) |
|---|---|---|---|
| Canvas / ground | `#F3EFE6` | `#12110F` | `#110C0A` |
| Surface | `#FBF8F1` | `#1C1A17` | `#1C1410` |
| Ink (primary text) | `#1A1814` | `#F4F0E6` | `#E7C7A8` |
| Secondary text | `#4A453C` | `#C9BBA8` | `#B89A80` |
| Blue, level “好”, circle | `#1E4B99` | `#A9C4F5` | — |
| Ochre, level “一般”, square | `#A67C00` | `#F0D078` | — |
| Red, level “偏高”, triangle | `#B42318` | `#FFB4A8` | — |
| Bad, level “差”, crossed square | `#1A1814` | `#F4F0E6` | — |
| Hairline | `#D9D2C5` | `#3A342C` | muted at 45% |
| Night accent | — | — | `#D47848` |
| Text on night accent | — | — | `#110C0A` |
| Night danger text | — | — | `#C96B5A` |
| Unverified badge fill | `#A67C00` with `#1A1814` text, both modes | | |

SF Pro is the system font. Key numbers use SF Pro Rounded (`.rounded`) at a text style so Dynamic Type can scale them. Text wraps or scales down to 50–60% before it truncates.

## Contrast

Ratios are WCAG 2.x relative luminance. Body text needs at least 4.5:1. A non-text mark against its neighbour needs at least 3:1. Large text (the night accent used as a button label at headline size, and the big numerals) also clears 4.5:1 here.

| Pair | Ratio | Role |
|---|---|---|
| `#1A1814` on `#F3EFE6` | 15.45:1 | Light primary text |
| `#4A453C` on `#F3EFE6` | 8.29:1 | Light secondary text |
| `#1A1814` on `#FBF8F1` | 16.71:1 | Light text on a card |
| `#4A453C` on `#FBF8F1` | 8.97:1 | Light secondary on a card |
| `#F4F0E6` on `#12110F` | 16.58:1 | Dark primary text |
| `#F4F0E6` on `#1C1A17` | 15.26:1 | Dark text on a card |
| `#C9BBA8` on `#12110F` | 10.03:1 | Dark secondary text |
| `#C9BBA8` on `#1C1A17` | 9.22:1 | Dark secondary on a card |
| `#F3EFE6` on `#1E4B99` | 7.26:1 | Word “好” on the light-mode blue circle |
| `#1A1814` on `#A67C00` | 4.65:1 | Word on ochre, and the unverified badge |
| `#A67C00` on `#F3EFE6` | 3.32:1 | Ochre square against paper (non-text) |
| `#F3EFE6` on `#B42318` | 5.73:1 | Word “偏高” on the light-mode red triangle |
| `#F3EFE6` on `#1A1814` | 15.45:1 | Word “差” on the light-mode black square |
| `#1A1814` on `#A9C4F5` | 10.05:1 | Word on the dark-mode blue |
| `#1A1814` on `#F0D078` | 11.82:1 | Word on the dark-mode ochre |
| `#1A1814` on `#FFB4A8` | 10.42:1 | Word on the dark-mode red |
| `#F0D078` on `#12110F` | 12.58:1 | Dark-mode ochre against the ground |
| `#E7C7A8` on `#110C0A` | 12.15:1 | Night primary text |
| `#E7C7A8` on `#1C1410` | 11.35:1 | Night text on a card |
| `#B89A80` on `#110C0A` | 7.38:1 | Night secondary text |
| `#B89A80` on `#1C1410` | 6.89:1 | Night secondary on a card |
| `#D47848` on `#110C0A` | 6.09:1 | Night accent as text or a control |
| `#110C0A` on `#D47848` | 6.09:1 | Label on the night primary button |
| `#C96B5A` on `#110C0A` | 5.31:1 | Night error text |

Yellow is never used as small text on paper. `#F2C14E` on `#F3EFE6` is only 1.46:1, so the moderate level uses ochre `#A67C00` in light mode.

## Status without color

| Level | Word | Shape | Light fill | Dark fill |
|---|---|---|---|---|
| 0 good | 好 | circle | `#1E4B99` | `#A9C4F5` |
| 1 moderate | 一般 | square | `#A67C00` | `#F0D078` |
| 2 poor | 偏高 | triangle | `#B42318` | `#FFB4A8` |
| 3 bad | 差 | square with an X | `#1A1814` | `#F4F0E6` |
| unknown | 未知 | open circle | secondary | secondary |

The noise dose is four square segments plus the percent and the same word. The air reading is one flat circle with the word inside it. Widgets in the accented (tinted) rendering mode switch the mark to a 4-step bar glyph so the level still reads when color is stripped.

## Ergonomics

- iPhone controls are at least 44 pt tall. Watch controls are at least 40 pt tall.
- One primary action per screen, in the bottom thumb zone: “开始今晚”, “开始专注” / “暂停”, “继续” on onboarding, “开始今晚监测” and “我醒了” on the watch.
- Destructive actions are separate: “停止守候” uses the night danger tint, “结束” on the focus screen is a bordered destructive button above the primary, “停止监测” sits alone at the bottom of the watch bedtime screen.
- Dynamic Type uses text styles and `ScaledMetric`. Key numbers set `minimumScaleFactor` so they shrink instead of turning into an ellipsis, and the surrounding scroll view keeps the rest of the screen reachable.
- Reduce Transparency turns custom glass into a solid material. Increase Contrast and Show Borders add a 1.5 pt stroke on custom glass. The air circle does not animate.
- Bedtime haptics are a soft impact at intensity 0.3. The watch alarm still repeats, but each pulse is `.click`, then `.directionUp`, not a full `.notification` buzz.
- Night screens avoid pure white and bright blue so the page stays usable with dark-adapted vision.

## Glass

`glassButton` and `GlassGroup` remain for daytime controls (focus primary, Zone fan and ANC choices, onboarding continue, the map record button). Sleep content and the watch heart-rate panel are solid, so the glass does not glow in a dark room. The system tab bar and navigation bar are untouched and pick up Liquid Glass on iOS 26 and later.
