#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Hareketli (animasyonlu GIF) hazir profil avatarlarini uretir.

NEDEN GIF: Secilen hazir avatar, kaydederken `avatars` bucket'ina yuklenip
normal bir avatar_url gibi saklaniyor. GIF secince uygulamanin HICBIR yerinde
degisiklik gerekmiyor - CachedNetworkImage / Image.network animasyonlu GIF'i
zaten oynatiyor. Lottie/SVG secseydik avatari gosteren her ekrani (feed,
yorumlar, sohbet, admin...) tek tek degistirmek gerekirdi.

BOYUT: Duz renkli geometrik sekiller bilinctli bir tercih - GIF'in LZW
sikistirmasi duz alanlarda cok iyi, yumusak gradyanlarda felaket. 30 avatarin
toplami ~1-2 MB'ta kaliyor.

Kullanim:
    python scripts/generate_animated_avatars.py

NOT: 56-79 arasi (sik sahneler + goz kirpan portreler) ayri betikle uretilir:
`scripts/generate_elegant_animated_avatars.py`. Bu betik yalniz 01-55'i uretir.

Cikti: assets/avatars_animated/avatar_anim_01.gif ... _55.gif
       (ilk 30: orijinal set - DEGISTIRILMEDI, ayni STYLES/PALETTES ile ayni
       sirada uretilir. 31-55 arasi: 25 yeni animasyon - 5 yeni stil
       (konfeti, spiral, patlama/starburst, parlama, sonsuzluk/infinity) x
       5 yeni palet.)

NEDEN LISTEYE DOKUNULMADI: STYLES/PALETTES listeleri index'e gore
kullaniliyor (`PALETTES[(s + group*3) % len(PALETTES)]`); bu listelerin
UZUNLUGUNU degistirmek bile ilk 30 dosyanin hangi stil+palet kombinasyonuyla
uretildigini kaydirir. Bu yuzden yeni stiller/paletler ayri NEW_STYLES /
NEW_PALETTES listelerine kondu ve main() sadece SONA yeni bir dongu ekledi.
"""

import math
import os
from PIL import Image, ImageDraw

SIZE = 192          # yayinlanan kare boyu (px)
SS = 3              # supersampling carpani (kenar yumusatma icin)
FRAMES = 16
FRAME_MS = 70

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets",
    "avatars_animated",
)

C = SIZE * SS  # supersample edilmis tuval boyu


def lerp(a, b, f):
    f = max(0.0, min(1.0, f))
    return tuple(int(round(a[i] + (b[i] - a[i]) * f)) for i in range(3))


# (arka plan, accent1, accent2, accent3)
PALETTES = [
    ((0x1B, 0x1F, 0x3B), (0xFF, 0x6B, 0x6B), (0xFF, 0xD9, 0x3D), (0x4E, 0xCD, 0xC4)),
    ((0x0F, 0x3D, 0x3E), (0x7B, 0xE4, 0x95), (0xF6, 0xF7, 0xD7), (0x32, 0x9D, 0x9C)),
    ((0x2B, 0x19, 0x3D), (0xFF, 0x8C, 0x42), (0xFF, 0x3C, 0x38), (0xFF, 0xF2, 0x75)),
    ((0x10, 0x2A, 0x43), (0x54, 0xC5, 0xF2), (0xFF, 0xFF, 0xFF), (0x2F, 0x80, 0xED)),
    ((0x3A, 0x0C, 0x2A), (0xFF, 0x6F, 0xD8), (0xFF, 0xD3, 0xA5), (0x9B, 0x5D, 0xE5)),
    ((0x14, 0x2B, 0x1A), (0xA8, 0xE0, 0x63), (0xF2, 0xFF, 0xE0), (0x4C, 0xAF, 0x50)),
    ((0x33, 0x22, 0x0C), (0xFF, 0xB3, 0x47), (0xFF, 0xE9, 0xA8), (0xE0, 0x6D, 0x06)),
    ((0x1A, 0x1A, 0x1A), (0xE5, 0xE5, 0xE5), (0xFF, 0x4D, 0x4D), (0x8C, 0x8C, 0x8C)),
    ((0x0B, 0x2E, 0x59), (0x00, 0xC9, 0xFF), (0x92, 0xFE, 0x9D), (0xFF, 0xFF, 0xFF)),
    ((0x40, 0x11, 0x24), (0xFF, 0xA5, 0xB5), (0xFF, 0xE5, 0x8A), (0xC7, 0x2C, 0x5B)),
]


def circle(d, cx, cy, r, fill):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def ring(d, cx, cy, r, width, fill):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=fill, width=int(width))


def rotated_square(cx, cy, half, angle):
    pts = []
    for k in range(4):
        a = angle + math.pi / 4 + k * math.pi / 2
        pts.append((cx + half * math.sqrt(2) * math.cos(a),
                    cy + half * math.sqrt(2) * math.sin(a)))
    return pts


# --------------------------------------------------------------- stiller
# Her stil: (draw, t, palette) alir; t 0..1 arasi dongusel zaman.

def style_orbit(d, t, p):
    bg, a1, a2, a3 = p
    cx = cy = C / 2
    circle(d, cx, cy, C * 0.17, a1)
    accents = [a2, a3, a2, a3, a2]
    for k in range(5):
        a = 2 * math.pi * (t + k / 5)
        x = cx + C * 0.33 * math.cos(a)
        y = cy + C * 0.33 * math.sin(a)
        circle(d, x, y, C * 0.075, accents[k])


def style_pulse(d, t, p):
    bg, a1, a2, a3 = p
    cx = cy = C / 2
    for k in range(3):
        f = (t + k / 3) % 1.0
        r = C * (0.10 + 0.36 * f)
        ring(d, cx, cy, r, C * 0.035, lerp(a1, bg, f))
    circle(d, cx, cy, C * 0.09, a2)


def style_wedges(d, t, p):
    bg, a1, a2, a3 = p
    cx = cy = C / 2
    r = C * 0.42
    box = [cx - r, cy - r, cx + r, cy + r]
    base = t * 360.0
    for k in range(6):
        start = base + k * 60
        d.pieslice(box, start, start + 44, fill=(a2 if k % 2 else a1))
    circle(d, cx, cy, C * 0.13, a3)


def style_bounce(d, t, p):
    bg, a1, a2, a3 = p
    cx = C / 2
    # 0..1..0 zipla, temas aninda hafif ezil.
    h = abs(math.sin(math.pi * t))
    top = C * 0.20 + (1 - h) * C * 0.34
    squash = 1.0 + 0.28 * (1 - h) ** 3
    rx = C * 0.15 * squash
    ry = C * 0.15 / squash
    d.rounded_rectangle(
        [C * 0.20, C * 0.74, C * 0.80, C * 0.79], radius=C * 0.03, fill=a3
    )
    d.ellipse([cx - rx, top - ry, cx + rx, top + ry], fill=a1)
    circle(d, cx - rx * 0.35, top - ry * 0.35, rx * 0.22, a2)


def style_wave(d, t, p):
    bg, a1, a2, a3 = p
    bars = 5
    slot = C * 0.62 / bars
    w = slot * 0.55
    left = C * 0.19
    for k in range(bars):
        v = 0.5 + 0.5 * math.sin(2 * math.pi * (t + k / bars))
        hgt = C * (0.14 + 0.44 * v)
        x = left + k * slot + (slot - w) / 2
        y0 = C / 2 - hgt / 2
        d.rounded_rectangle(
            [x, y0, x + w, y0 + hgt],
            radius=w / 2,
            fill=(a1 if k % 2 == 0 else a2),
        )


def style_face(d, t, p):
    bg, a1, a2, a3 = p
    cx = cy = C / 2
    circle(d, cx, cy, C * 0.36, a2)
    # Goz kirpma: dongunun kucuk bir diliminde gozler kapanir.
    blink = 1.0
    if 0.42 < t < 0.56:
        blink = abs(math.cos(math.pi * (t - 0.42) / 0.14)) * 0.9 + 0.1
    ex, ey, er = C * 0.115, C * 0.06, C * 0.045
    for sign in (-1, 1):
        d.ellipse(
            [cx + sign * ex - er, cy - ey - er * blink,
             cx + sign * ex + er, cy - ey + er * blink],
            fill=bg,
        )
    d.arc(
        [cx - C * 0.16, cy - C * 0.04, cx + C * 0.16, cy + C * 0.20],
        20, 160, fill=bg, width=int(C * 0.028),
    )
    # Yanaklar nefes alir gibi buyuyup kuculur.
    cheek = C * (0.030 + 0.012 * math.sin(2 * math.pi * t))
    circle(d, cx - C * 0.21, cy + C * 0.05, cheek, a1)
    circle(d, cx + C * 0.21, cy + C * 0.05, cheek, a1)


def style_squares(d, t, p):
    bg, a1, a2, a3 = p
    cx = cy = C / 2
    specs = [(0.36, a1, 1.0), (0.25, a2, -1.6), (0.14, a3, 2.4)]
    for half, color, speed in specs:
        d.polygon(
            rotated_square(cx, cy, C * half, 2 * math.pi * t * speed), fill=color
        )


def style_comet(d, t, p):
    bg, a1, a2, a3 = p
    cx = cy = C / 2
    ring(d, cx, cy, C * 0.33, C * 0.02, lerp(a3, bg, 0.55))
    for k in range(7):
        a = 2 * math.pi * (t - k * 0.028)
        f = k / 7.0
        x = cx + C * 0.33 * math.cos(a)
        y = cy + C * 0.33 * math.sin(a)
        circle(d, x, y, C * (0.085 - 0.008 * k), lerp(a1, bg, f))
    circle(d, cx, cy, C * 0.10, a2)


def style_petals(d, t, p):
    bg, a1, a2, a3 = p
    cx = cy = C / 2
    grow = 1.0 + 0.12 * math.sin(2 * math.pi * t)
    for k in range(6):
        a = 2 * math.pi * (t * 0.5 + k / 6)
        px = cx + C * 0.20 * math.cos(a) * grow
        py = cy + C * 0.20 * math.sin(a) * grow
        circle(d, px, py, C * 0.135 * grow, a1 if k % 2 == 0 else a2)
    circle(d, cx, cy, C * 0.11, a3)


def style_arc(d, t, p):
    bg, a1, a2, a3 = p
    cx = cy = C / 2
    r = C * 0.34
    box = [cx - r, cy - r, cx + r, cy + r]
    ring(d, cx, cy, r, C * 0.055, lerp(a3, bg, 0.6))
    start = t * 360.0
    d.arc(box, start, start + 110, fill=a1, width=int(C * 0.055))
    d.arc(box, start + 180, start + 250, fill=a2, width=int(C * 0.055))
    circle(d, cx, cy, C * 0.11, a2)


STYLES = [
    style_orbit,
    style_pulse,
    style_wedges,
    style_bounce,
    style_wave,
    style_face,
    style_squares,
    style_comet,
    style_petals,
    style_arc,
]


# ----------------------------------------------------- yeni stiller (31-55)
# Bu fonksiyonlar yalnizca NEW_STYLES uzerinden, 31. dosyadan itibaren
# kullanilir - STYLES listesine EKLENMEZ (yukaridaki index kaymasi riski).

def style_confetti(d, t, p):
    bg, a1, a2, a3 = p
    cols = [a1, a2, a3]
    n = 10
    for k in range(n):
        phase = (t + k / n) % 1.0
        x = C * (0.12 + 0.76 * ((k * 0.37) % 1.0))
        y = phase * C * 1.3 - C * 0.12
        half = C * 0.032
        d.rectangle([x - half, y - half, x + half, y + half], fill=cols[k % 3])


def style_spiral(d, t, p):
    bg, a1, a2, a3 = p
    cx = cy = C / 2
    cols = [a1, a2, a3]
    n = 8
    for k in range(n):
        f = k / n
        ang = 2 * math.pi * (t + f * 1.6)
        rad = C * 0.05 + C * 0.34 * f
        x = cx + rad * math.cos(ang)
        y = cy + rad * math.sin(ang)
        r = C * (0.018 + 0.05 * (1 - f))
        circle(d, x, y, r, cols[k % 3])


def style_starburst(d, t, p):
    bg, a1, a2, a3 = p
    cx = cy = C / 2
    points = 5
    pulse = 0.85 + 0.15 * math.sin(2 * math.pi * t * 2)
    outer, inner = C * 0.36 * pulse, C * 0.15 * pulse
    rot = t * 2 * math.pi / points
    pts = []
    for i in range(points * 2):
        ang = rot + i * math.pi / points
        r = outer if i % 2 == 0 else inner
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    d.polygon(pts, fill=a1)
    for k in range(4):
        a = 2 * math.pi * (t * 0.6 + k / 4)
        x = cx + C * 0.42 * math.cos(a)
        y = cy + C * 0.42 * math.sin(a)
        tw = abs(math.sin(2 * math.pi * (t * 3 + k / 4)))
        circle(d, x, y, C * 0.022 * tw, a3)
    circle(d, cx, cy, C * 0.09, a2)


def style_glow(d, t, p):
    bg, a1, a2, a3 = p
    cx = cy = C / 2
    cols = [a1, a2, a3]
    cycle = (t * 3) % 3
    seg = int(cycle)
    f = cycle - seg
    col = lerp(cols[seg], cols[(seg + 1) % 3], f)
    breathe = 0.85 + 0.15 * math.sin(2 * math.pi * t)
    for i, fr in enumerate((1.0, 0.7, 0.42)):
        circle(d, cx, cy, C * 0.30 * fr * breathe, lerp(col, bg, i * 0.28))


def style_infinity(d, t, p):
    bg, a1, a2, a3 = p
    cx = cy = C / 2
    cols = [a1, a2, a3]
    trail = 8
    for k in range(trail):
        ft = (t - k * 0.02) % 1.0
        ang = 2 * math.pi * ft
        scale = C * 0.30
        x = cx + scale * math.sin(ang)
        y = cy + scale * math.sin(ang) * math.cos(ang)
        r = max(C * 0.05 * (1 - k / trail), 1)
        circle(d, x, y, r, cols[k % 3])


NEW_STYLES = [
    style_confetti,
    style_spiral,
    style_starburst,
    style_glow,
    style_infinity,
]

# Yeni parlak paletler - orijinal PALETTES listesine EKLENMEDI (index kaymasi
# yaratmamak icin), sadece 31+ icin kullanilir.
NEW_PALETTES = [
    ((0x1E, 0x12, 0x2B), (0xC7, 0x7D, 0xFF), (0x5C, 0xE1, 0xE6), (0xFF, 0xE1, 0x66)),
    ((0x0A, 0x22, 0x1C), (0x3D, 0xDC, 0x97), (0xFF, 0xE0, 0x8A), (0x27, 0x8C, 0xA8)),
    ((0x2B, 0x0E, 0x14), (0xFF, 0x5C, 0x8A), (0xFF, 0xC1, 0x4D), (0xB8, 0x3B, 0x5E)),
    ((0x0D, 0x1B, 0x2A), (0x4F, 0xC3, 0xF7), (0xFF, 0xFF, 0xFF), (0x1D, 0x6F, 0xA5)),
    ((0x24, 0x1E, 0x0A), (0xFF, 0xD5, 0x4F), (0xEF, 0xA8, 0x3A), (0x8A, 0x6D, 0x1E)),
]


def build(style, palette):
    bg = palette[0]
    frames = []
    for i in range(FRAMES):
        big = Image.new("RGB", (C, C), bg)
        d = ImageDraw.Draw(big)
        style(d, i / FRAMES, palette)
        small = big.resize((SIZE, SIZE), Image.LANCZOS)
        frames.append(small.quantize(colors=64, method=Image.MEDIANCUT))
    return frames


def _save_gif(path, frames):
    frames[0].save(
        path,
        save_all=True,
        append_images=frames[1:],
        duration=FRAME_MS,
        loop=0,
        optimize=True,
        disposal=2,
    )
    return os.path.getsize(path)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    index = 0
    # --- orijinal 30 avatar: STYLES/PALETTES DEGISTIRILMEDI, index birebir
    # korunuyor (script tekrar calisirsa bu 30 dosya birebir ayni cikar) ---
    for group in range(3):
        for s in range(len(STYLES)):
            index += 1
            palette = PALETTES[(s + group * 3) % len(PALETTES)]
            frames = build(STYLES[s], palette)
            path = os.path.join(OUT_DIR, "avatar_anim_%02d.gif" % index)
            size = _save_gif(path, frames)
            total += size
            print("%s  %6.1f KB" % (os.path.basename(path), size / 1024))

    # --- yeni 25 avatar: NEW_STYLES x NEW_PALETTES, 31'den devam ---
    for palette in NEW_PALETTES:
        for style in NEW_STYLES:
            index += 1
            frames = build(style, palette)
            path = os.path.join(OUT_DIR, "avatar_anim_%02d.gif" % index)
            size = _save_gif(path, frames)
            total += size
            print("%s  %6.1f KB" % (os.path.basename(path), size / 1024))

    print("TOPLAM: %.2f MB (%d dosya)" % (total / 1024 / 1024, index))


if __name__ == "__main__":
    main()
