#!/usr/bin/env python3
"""Draw labelled Bauhaus mockups for docs/previews. Not device screenshots."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1] / "docs" / "previews"
PAPER = (243, 239, 230)
SURFACE = (251, 248, 241)
INK = (26, 24, 20)
MUTED = (74, 69, 60)
BLUE = (30, 75, 153)
OCHRE = (166, 124, 0)
RED = (180, 35, 24)
HAIR = (217, 210, 197)
NIGHT = (17, 12, 10)
NSURF = (28, 20, 16)
NINK = (231, 199, 168)
NMUTED = (184, 154, 128)
AMBER = (212, 120, 72)
NDANGER = (201, 107, 90)


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
    draw.text((12, h - 28), "MOCKUP  示意稿  ·  不是真机截图", font=font(16, True), fill=(243, 239, 230))


def phone(title, paint):
    w, h = 860, 1600
    img = Image.new("RGB", (w, h), PAPER)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((24, 24, w - 24, h - 48), radius=36, outline=INK, width=3)
    d.text((48, 48), title, font=font(28, True), fill=INK)
    paint(d, w, h)
    stamp(d, w, h)
    return img


def circle(d, box, fill):
    d.ellipse(box, fill=fill)


def square(d, box, fill):
    d.rectangle(box, fill=fill)


def triangle(d, box, fill):
    x0, y0, x1, y1 = box
    d.polygon([( (x0+x1)/2, y0), (x1, y1), (x0, y1)], fill=fill)


def sleep(d, w, h):
    d.rectangle((24, 24, w - 24, h - 48), fill=NIGHT)
    d.text((56, 90), "SleepPause", font=font(22), fill=NMUTED)
    d.rounded_rectangle((56, 140, w - 56, 420), radius=6, fill=NSURF, outline=NMUTED)
    d.text((80, 170), "守候中", font=font(54, True), fill=NINK)
    d.text((80, 250), "睡着后自动暂停播放", font=font(26), fill=NMUTED)
    d.text((80, 292), "降噪保持开启", font=font(26), fill=NMUTED)
    circle(d, (w - 160, 180, w - 100, 240), AMBER)
    d.rounded_rectangle((56, 460, w - 56, 760), radius=6, fill=NSURF, outline=NMUTED)
    d.text((80, 490), "助眠声音", font=font(28, True), fill=NINK)
    d.text((80, 540), "实时生成，不循环", font=font(22), fill=NMUTED)
    circle(d, (w - 180, 500, w - 100, 580), AMBER)
    d.rounded_rectangle((56, h - 220, w - 56, h - 120), radius=8, fill=NDANGER)
    d.text((250, h - 190), "停止守候", font=font(32, True), fill=NIGHT)


def zone(d, w, h):
    d.rectangle((40, 100, w - 40, 112), fill=BLUE)
    d.text((56, 140), "Dyson Zone", font=font(36, True), fill=INK)
    circle(d, (70, 230, 310, 470), BLUE)
    d.text((150, 320), "好", font=font(40, True), fill=PAPER)
    d.text((70, 490), "空气好", font=font(28, True), fill=INK)
    d.text((70, 530), "NO2 18 ppb", font=font(20), fill=MUTED)
    d.text((400, 240), "35%", font=font(48, True), fill=INK)
    d.text((400, 310), "噪音剂量", font=font(20), fill=MUTED)
    for i, col in enumerate((BLUE, BLUE, HAIR, HAIR)):
        square(d, (400 + i * 90, 360, 470 + i * 90, 400), col)
    circle(d, (400, 424, 436, 460), BLUE)
    d.text((448, 428), "好", font=font(22, True), fill=INK)
    d.rounded_rectangle((56, 620, w - 56, 980), radius=6, outline=HAIR, width=2)
    d.text((80, 660), "电量 72%", font=font(24), fill=INK)
    d.rounded_rectangle((80, 740, 380, 820), radius=6, outline=BLUE, width=3)
    d.text((120, 762), "降噪", font=font(26, True), fill=INK)
    d.rounded_rectangle((420, 740, 760, 820), radius=6, outline=BLUE, width=3)
    d.text((470, 762), "风扇", font=font(26, True), fill=INK)
    d.text((80, 880), "圆 = 好    方 = 一般", font=font(22), fill=MUTED)
    d.text((80, 920), "三角 = 偏高    叉 = 差", font=font(22), fill=MUTED)


def onboarding(d, w, h):
    d.rectangle((40, 100, w - 40, 112), fill=BLUE)
    square(d, (70, 180, 170, 280), BLUE)
    d.text((70, 320), "睡着了，音乐自动停", font=font(36, True), fill=INK)
    d.text((70, 390), "手表判断入睡，手机暂停播放。", font=font(24), fill=MUTED)
    d.text((70, 430), "降噪整晚保持开启。", font=font(24), fill=MUTED)
    d.rounded_rectangle((70, 520, w - 70, 860), radius=6, fill=SURFACE, outline=HAIR)
    for i, line in enumerate(("手表：心率 + 静止", "iPhone：暂停播放", "Zone：空气、噪音、风扇")):
        d.text((100, 560 + i * 80), line, font=font(26), fill=INK)
    d.rounded_rectangle((70, h - 280, w - 70, h - 180), radius=10, fill=BLUE)
    d.text((340, h - 250), "继续", font=font(32, True), fill=PAPER)
    d.text((380, h - 150), "跳过", font=font(20), fill=MUTED)


def watch(d, w, h):
    img_w = w
    d.rectangle((0, 0, img_w, h), fill=(30, 26, 24))
    cx, cy, r = img_w // 2, 620, 250
    d.rounded_rectangle((cx - r, cy - r - 40, cx + r, cy + r + 220), radius=80, fill=NIGHT, outline=NMUTED, width=4)
    d.text((cx - 70, cy - 180), "18", font=font(92, True), fill=NINK)
    d.text((cx - 90, cy - 60), "静止分钟", font=font(22), fill=NMUTED)
    d.rounded_rectangle((cx - 140, cy + 10, cx + 140, cy + 28), radius=8, fill=NSURF)
    d.rounded_rectangle((cx - 140, cy + 10, cx - 20, cy + 28), radius=8, fill=AMBER)
    d.text((cx - 80, cy + 50), "心率 58", font=font(22), fill=NINK)
    d.rounded_rectangle((cx - 120, cy + 120, cx + 120, cy + 190), radius=8, outline=NDANGER, width=3)
    d.text((cx - 70, cy + 138), "停止监测", font=font(22, True), fill=NDANGER)


def widgets(d, w, h):
    d.rectangle((40, 120, 400, 480), fill=PAPER, outline=INK, width=2)
    d.text((60, 150), "72%", font=font(42, True), fill=INK)
    circle(d, (60, 230, 100, 270), BLUE)
    d.text((116, 236), "空气好", font=font(24, True), fill=INK)
    d.text((60, 320), "62 dB", font=font(36, True), fill=INK)
    square(d, (60, 390, 90, 420), OCHRE)
    d.text((104, 392), "一般", font=font(22, True), fill=INK)
    d.rectangle((440, 120, 820, 360), fill=(18, 17, 15), outline=INK, width=2)
    d.text((460, 150), "实时活动", font=font(22), fill=(244, 240, 230))
    circle(d, (460, 210, 510, 260), (169, 196, 245))
    d.text((530, 220), "好  ·  62", font=font(32, True), fill=(244, 240, 230))
    d.text((60, 540), "形状在着色主屏幕下仍然可读", font=font(24), fill=MUTED)


def glass_zone(d, w, h):
    d.text((56, 130), "控件用玻璃，内容是平的", font=font(28, True), fill=INK)
    d.rounded_rectangle((56, 200, w - 56, 520), radius=28, fill=(255, 255, 255), outline=(180, 190, 210), width=2)
    d.text((80, 230), "玻璃 · 仅控件", font=font(18), fill=BLUE)
    d.rounded_rectangle((80, 300, 380, 380), radius=24, fill=(210, 225, 245))
    d.text((140, 324), "降噪", font=font(26, True), fill=BLUE)
    d.rounded_rectangle((420, 300, 760, 380), radius=24, fill=(236, 236, 236))
    d.text((500, 324), "通透", font=font(26), fill=INK)
    d.rounded_rectangle((56, 580, w - 56, 980), radius=6, fill=SURFACE, outline=HAIR)
    d.text((80, 620), "空气", font=font(22), fill=MUTED)
    circle(d, (80, 680, 200, 800), BLUE)
    d.text((112, 720), "好", font=font(28, True), fill=PAPER)
    triangle(d, (240, 680, 360, 800), RED)
    d.text((400, 720), "偏高", font=font(28, True), fill=INK)


def focus(d, w, h):
    d.rectangle((40, 100, w - 40, 112), fill=BLUE)
    d.text((70, 160), "专注", font=font(36, True), fill=INK)
    d.text((70, 250), "专注中", font=font(24), fill=MUTED)
    d.text((70, 300), "24:18", font=font(92, True), fill=INK)
    d.text((70, 430), "已完成 2 个番茄", font=font(24), fill=MUTED)
    d.rounded_rectangle((70, h - 360, w - 70, h - 270), radius=8, outline=RED, width=3)
    d.text((360, h - 330), "结束", font=font(28, True), fill=RED)
    d.rounded_rectangle((70, h - 240, w - 70, h - 140), radius=16, fill=(190, 210, 240))
    d.text((340, h - 210), "暂停", font=font(32, True), fill=BLUE)
    d.text((70, h - 110), "主操作在底部，结束与它分开", font=font(22), fill=MUTED)


def settings(d, w, h):
    d.text((56, 120), "夜间色，不是亮蓝", font=font(30, True), fill=NINK)
    d.rectangle((24, 24, w - 24, h - 48), fill=NIGHT)
    d.text((56, 120), "夜间色，不是亮蓝", font=font(30, True), fill=NINK)
    rows = [("同时暂停 Apple Music", True), ("写入健康", False), ("授权健康数据", None)]
    y = 220
    for label, on in rows:
        d.rounded_rectangle((56, y, w - 56, y + 100), radius=6, fill=NSURF)
        d.text((80, y + 32), label, font=font(24), fill=NINK)
        if on is not None:
            col = AMBER if on else (60, 48, 42)
            d.rounded_rectangle((w - 180, y + 30, w - 90, y + 70), radius=16, fill=col)
        y += 120
    d.text((56, y + 20), "文字 #E7C7A8  ·  强调 #D47848", font=font(22), fill=NMUTED)
    d.text((56, y + 60), "对比度见 docs/DESIGN.md", font=font(22), fill=NMUTED)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    pages = {
        "01-sleep-tab.png": lambda: phone("睡眠", sleep),
        "02-zone-dashboard.png": lambda: phone("Zone", zone),
        "03-onboarding.png": lambda: phone("引导", onboarding),
        "04-watch.png": lambda: watch_image(),
        "05-widgets.png": lambda: phone("小组件", widgets),
        "06-glass-zone.png": lambda: phone("玻璃只在控件", glass_zone),
        "07-glass-sleep-focus.png": lambda: phone("专注", focus),
        "08-glass-ios27-settings.png": lambda: phone("睡眠设置", settings),
    }
    for name, make in pages.items():
        img = make()
        img.save(OUT / name, "PNG")
        print(name, img.size)


def watch_image():
    w, h = 700, 900
    img = Image.new("RGB", (w, h), (24, 20, 18))
    d = ImageDraw.Draw(img)
    d.text((24, 24), "Apple Watch", font=font(22, True), fill=NINK)
    watch(d, w, h)
    stamp(d, w, h)
    return img


if __name__ == "__main__":
    main()
