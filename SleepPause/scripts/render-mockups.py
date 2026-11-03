#!/usr/bin/env python3
"""Draw labelled Apple-style mockups for docs/previews. Not device screenshots."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1] / "docs" / "previews"
GROUP = (242, 242, 247)
CARD = (255, 255, 255)
INK = (0, 0, 0)
SEC = (99, 99, 102)
INDIGO = (88, 86, 214)
GREEN = (52, 199, 89)
YELLOW = (255, 204, 0)
ORANGE = (255, 149, 0)
RED = (255, 59, 48)
TEAL = (48, 176, 199)
DARK = (0, 0, 0)
DARKCARD = (28, 28, 30)
DARKINK = (255, 255, 255)
DARKSEC = (174, 174, 178)
WHITE = (255, 255, 255)


class MixedFont:
    """Latin from DejaVu (digits included) and Chinese from Droid Sans Fallback."""

    def __init__(self, size, bold=False):
        self.size = size
        latin = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
        self.latin = ImageFont.truetype(latin, size)
        self.cjk = ImageFont.truetype("/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf", size)

    def pick(self, ch):
        return self.cjk if ord(ch) > 127 else self.latin


def font(size, bold=False):
    return MixedFont(size, bold)


def _install_mixed_text():
    original = ImageDraw.ImageDraw.text

    def text(self, xy, content, fill=None, font=None, anchor=None, spacing=4, align="left", *args, **kwargs):
        if not isinstance(font, MixedFont):
            return original(self, xy, content, fill=fill, font=font, anchor=anchor, spacing=spacing, align=align)
        x, y = xy
        for ch in str(content):
            face = font.pick(ch)
            original(self, (x, y), ch, fill=fill, font=face)
            x += self.textlength(ch, font=face)

    ImageDraw.ImageDraw.text = text


_install_mixed_text()


def stamp(draw, w, h):
    draw.rectangle((0, h - 36, w, h), fill=(0, 0, 0))
    draw.text((12, h - 28), "MOCKUP  示意稿  ·  不是真机截图", font=font(16, True), fill=WHITE)


def phone(bg, paint):
    w, h = 860, 1600
    img = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(img)
    paint(d, w, h)
    stamp(d, w, h)
    return img


def card(d, box, fill=CARD, radius=22):
    d.rounded_rectangle(box, radius=radius, fill=fill)


def icon(d, xy, fill, glyph):
    x, y = xy
    d.rounded_rectangle((x, y, x + 36, y + 36), radius=8, fill=fill)
    d.text((x + 8, y + 4), glyph, font=font(22, True), fill=WHITE)


def sleep(d, w, h):
    d.text((48, 70), "睡眠", font=font(44, True), fill=DARKINK)
    card(d, (40, 160, w - 40, 460), DARKCARD)
    icon(d, (64, 188), INDIGO, "Z")
    d.text((112, 192), "睡眠", font=font(22, True), fill=INDIGO)
    d.text((64, 250), "守候中", font=font(52, True), fill=DARKINK)
    d.text((64, 330), "睡着后自动暂停播放", font=font(24), fill=DARKSEC)
    d.text((64, 372), "降噪保持开启", font=font(24), fill=DARKSEC)
    card(d, (40, 490, w - 40, 760), DARKCARD)
    icon(d, (64, 516), ORANGE, "dB")
    d.text((112, 520), "噪音剂量", font=font(22, True), fill=ORANGE)
    d.text((64, 580), "35", font=font(56, True), fill=DARKINK)
    d.text((160, 610), "%", font=font(24), fill=DARKSEC)
    d.text((64, 660), "正常  ·  好", font=font(22), fill=DARKSEC)
    d.rounded_rectangle((64, 710, w - 80, 730), radius=6, fill=(48, 48, 54))
    d.polygon([(90, 728), (220, 700), (400, 718), (620, 690), (760, 724)], fill=ORANGE)
    d.rounded_rectangle((48, h - 210, w - 48, h - 110), radius=16, fill=RED)
    d.text((300, h - 180), "停止守候", font=font(30, True), fill=WHITE)


def zone(d, w, h):
    d.text((48, 70), "Dyson Zone", font=font(40, True), fill=INK)
    card(d, (40, 160, w - 40, 560))
    icon(d, (64, 188), TEAL, "A")
    d.text((112, 192), "空气", font=font(22, True), fill=TEAL)
    d.text((64, 250), "好", font=font(48, True), fill=INK)
    d.text((64, 320), "NO2 18 ppb", font=font(22), fill=SEC)
    icon(d, (430, 188), ORANGE, "dB")
    d.text((478, 192), "噪音剂量", font=font(22, True), fill=ORANGE)
    d.text((430, 250), "35%", font=font(48, True), fill=INK)
    d.text((430, 330), "好", font=font(22), fill=SEC)
    card(d, (40, 590, w - 40, 900))
    d.text((64, 620), "72", font=font(48, True), fill=INK)
    d.text((150, 648), "dB 环境", font=font(24), fill=SEC)
    d.text((64, 700), "正常", font=font(22, True), fill=GREEN)
    d.rounded_rectangle((64, 780, 360, 860), radius=22, fill=(232, 232, 255))
    d.text((150, 804), "降噪", font=font(26, True), fill=INDIGO)
    d.rounded_rectangle((400, 780, 760, 860), radius=22, fill=(236, 236, 240))
    d.text((500, 804), "风扇", font=font(26), fill=INK)


def onboarding(d, w, h):
    icon(d, (56, 80), INDIGO, "Z")
    d.text((56, 150), "我的耳机", font=font(44, True), fill=INK)
    d.text((56, 230), "Zone、AirPods 或其他耳机。", font=font(24), fill=SEC)
    d.text((56, 270), "没有 Zone 也能暂停播放。", font=font(24), fill=SEC)
    card(d, (40, 360, w - 40, 760))
    rows = ("Dyson Zone", "AirPods / Beats", "其他蓝牙或有线耳机")
    for i, line in enumerate(rows):
        y = 400 + i * 110
        d.text((80, y + 24), line, font=font(26), fill=INK)
        mark = "✓" if i == 0 else ""
        d.text((w - 140, y + 24), mark, font=font(28, True), fill=INDIGO)
    d.rounded_rectangle((48, h - 250, w - 48, h - 150), radius=16, fill=INDIGO)
    d.text((360, h - 220), "继续", font=font(30, True), fill=WHITE)
    d.text((380, h - 120), "跳过", font=font(20), fill=SEC)


def watch_image():
    w, h = 700, 900
    img = Image.new("RGB", (w, h), DARK)
    d = ImageDraw.Draw(img)
    for i in range(h):
        t = i / h
        col = tuple(int(INDIGO[c] * (1 - t) + DARK[c] * t) for c in range(3))
        d.line((0, i, w, i), fill=col)
    d.text((24, 24), "Apple Watch", font=font(22, True), fill=DARKINK)
    cx, cy = w // 2, 430
    d.text((cx - 50, cy - 160), "18", font=font(92, True), fill=DARKINK)
    d.text((cx - 80, cy - 40), "静止分钟", font=font(22), fill=DARKSEC)
    d.text((cx - 40, cy + 10), "静止", font=font(22, True), fill=INDIGO)
    d.rounded_rectangle((cx - 140, cy + 60, cx + 140, cy + 78), radius=8, fill=(255, 255, 255))
    d.rounded_rectangle((cx - 140, cy + 60, cx - 10, cy + 78), radius=8, fill=INDIGO)
    d.rounded_rectangle((cx - 150, cy + 140, cx + 150, cy + 220), radius=22, fill=RED)
    d.text((cx - 70, cy + 162), "停止监测", font=font(22, True), fill=WHITE)
    stamp(d, w, h)
    return img


def widgets(d, w, h):
    card(d, (40, 120, 400, 500))
    icon(d, (60, 148), TEAL, "A")
    d.text((108, 152), "空气", font=font(20, True), fill=TEAL)
    d.text((60, 210), "好", font=font(40, True), fill=INK)
    d.text((60, 280), "62", font=font(48, True), fill=INK)
    d.text((150, 308), "dB", font=font(22), fill=SEC)
    d.text((60, 360), "正常", font=font(22, True), fill=GREEN)
    d.text((60, 420), "剂量 35%", font=font(22), fill=SEC)
    card(d, (440, 120, 820, 420), (28, 28, 30))
    d.text((460, 150), "实时活动", font=font(22), fill=DARKSEC)
    icon(d, (460, 210), GREEN, "好")
    d.text((520, 214), "好", font=font(28, True), fill=DARKINK)
    d.text((460, 290), "62", font=font(48, True), fill=DARKINK)
    d.text((60, 560), "符号和文字一起出现，不单靠颜色", font=font(24), fill=SEC)


def glass_zone(d, w, h):
    d.text((48, 80), "Dyson Zone", font=font(40, True), fill=INK)
    d.text((48, 150), "内容在分组卡片里，玻璃只在按钮上", font=font(24), fill=SEC)
    card(d, (40, 230, w - 40, 620))
    icon(d, (64, 260), TEAL, "A")
    d.text((112, 264), "空气", font=font(22, True), fill=TEAL)
    d.text((64, 330), "好", font=font(48, True), fill=INK)
    d.text((64, 410), "NO2 18 ppb", font=font(22), fill=SEC)
    d.text((64, 470), "电量 72%  ·  已佩戴", font=font(22), fill=SEC)
    d.rounded_rectangle((64, 680, 380, 780), radius=28, fill=(210, 210, 255))
    d.text((150, 712), "降噪", font=font(28, True), fill=INDIGO)
    d.rounded_rectangle((420, 680, 780, 780), radius=28, fill=(255, 255, 255))
    d.text((520, 712), "通透", font=font(28), fill=INK)
    d.text((48, 840), "主按钮是系统玻璃，列表保持分组背景", font=font(22), fill=SEC)


def focus(d, w, h):
    d.text((48, 70), "专注", font=font(44, True), fill=INK)
    card(d, (40, 170, w - 40, 520))
    icon(d, (64, 200), ORANGE, "T")
    d.text((112, 204), "专注中", font=font(22, True), fill=ORANGE)
    d.text((64, 270), "24:18", font=font(84, True), fill=INK)
    d.text((64, 400), "已完成 2 个番茄", font=font(24), fill=SEC)
    d.rounded_rectangle((48, h - 360, w - 48, h - 270), radius=16, outline=RED, width=3)
    d.text((370, h - 330), "结束", font=font(28, True), fill=RED)
    d.rounded_rectangle((48, h - 240, w - 48, h - 140), radius=16, fill=ORANGE)
    d.text((360, h - 210), "暂停", font=font(30, True), fill=WHITE)
    d.text((48, h - 110), "主操作在底部，结束与它分开", font=font(22), fill=SEC)


def settings(d, w, h):
    d.text((48, 70), "睡眠", font=font(44, True), fill=DARKINK)
    card(d, (40, 170, w - 40, 900), DARKCARD)
    rows = (
        ("我的耳机", "AirPods", INDIGO),
        ("写入健康", "开", INDIGO),
        ("授权健康数据", "", INDIGO),
    )
    y = 210
    for title, value, tint in rows:
        d.text((70, y + 28), title, font=font(26), fill=DARKINK)
        d.text((w - 280, y + 28), value, font=font(24), fill=tint)
        y += 120
    d.text((70, y + 40), "同一分钟不叠加耳机音量和环境噪音", font=font(22), fill=DARKSEC)
    d.text((70, y + 90), "系统深色  ·  靛蓝  ·  分组列表", font=font(22), fill=DARKSEC)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    pages = {
        "01-sleep-tab.png": lambda: phone(DARK, sleep),
        "02-zone-dashboard.png": lambda: phone(GROUP, zone),
        "03-onboarding.png": lambda: phone(GROUP, onboarding),
        "04-watch.png": watch_image,
        "05-widgets.png": lambda: phone(GROUP, widgets),
        "06-glass-zone.png": lambda: phone(GROUP, glass_zone),
        "07-glass-sleep-focus.png": lambda: phone(GROUP, focus),
        "08-glass-ios27-settings.png": lambda: phone(DARK, settings),
    }
    for name, make in pages.items():
        img = make()
        img.save(OUT / name, "PNG")
        print(name, img.size)


if __name__ == "__main__":
    main()
