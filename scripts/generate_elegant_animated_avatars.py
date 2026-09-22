#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sik hareketli (GIF) profil avatarlari: avatar_anim_56 ... avatar_anim_79.

  56-67  soyut/sik tasarimlar (aurora, sivi altin, neon halka, cam kure,
         takimyildiz, dalgalar, bokeh, holografik prizma, lav lambasi,
         mandala, gun batimi, galaksi)
  68-79  hareketli PORTRELER: gercekci karakterler goz kirpar, hafifce sallanir
         ve nefes alir; arkalarinda yumusak hareketli bir sahne akar.

Kullanim:
    # portre kareleri (bir kez):
    $env:GEN_ANIMATED_PORTRAITS='1'
    flutter test test/tools/generate_animated_portrait_frames_test.dart
    python scripts/generate_elegant_animated_avatars.py

Eski `generate_animated_avatars.py` (01-55) DEGISTIRILMEDI; dosya adlari
kullanicilarin sectigi avatar_url'ye bagli oldugundan yalnizca sona eklenir.

NEDEN GIF: bkz. generate_animated_avatars.py - avatari gosteren hicbir ekrani
degistirmeden animasyon oynatilir. Yumusak gradyanlar GIF'te zor; her animasyon
tek bir 128-160 renklik ORTAK palet + Floyd-Steinberg ile kucultuluyor, boylece
her GIF ~100-250 KB'ta kaliyor.
"""

import glob
import math
import os
import random
import re
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 192          # yayin boyu (px)
SS = 2              # supersampling
C = SIZE * SS
N = 20              # kare sayisi
MS = 65             # kare suresi (ms)
TAU = 2 * math.pi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "avatars_animated")
FRAMES_DIR = os.path.join(ROOT, "build", "anim_frames")
FIRST_INDEX = 56


# ------------------------------------------------------------------ yardimci
def lerp(a, b, f):
    f = max(0.0, min(1.0, f))
    return tuple(int(round(a[i] + (b[i] - a[i]) * f)) for i in range(3))


def hsv(h, s, v):
    """0-1 araliginda HSV -> RGB demeti."""
    import colorsys
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, s, v)
    return (int(r * 255), int(g * 255), int(b * 255))


def vgrad(top, bottom):
    g = Image.linear_gradient("L").resize((C, C), Image.BILINEAR)
    return Image.composite(Image.new("RGB", (C, C), bottom),
                           Image.new("RGB", (C, C), top), g).convert("RGBA")


def rgrad(cx, cy, r, inner, outer):
    g = Image.radial_gradient("L").resize((int(2 * r), int(2 * r)), Image.BILINEAR)
    mask = Image.new("L", (C, C), 255)
    mask.paste(g, (int(cx - r), int(cy - r)))
    return Image.composite(Image.new("RGB", (C, C), outer),
                           Image.new("RGB", (C, C), inner), mask).convert("RGBA")


def layer():
    return Image.new("RGBA", (C, C), (0, 0, 0, 0))


def glow(img, draw_fn, radius):
    """draw_fn(ImageDraw) ile bir katman ciz, blurla, img'e bindir."""
    lay = layer()
    draw_fn(ImageDraw.Draw(lay))
    lay = lay.filter(ImageFilter.GaussianBlur(radius * SS / 2))
    img.alpha_composite(lay)


def circle(d, cx, cy, r, fill):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def star4(d, cx, cy, r, fill):
    """Dort uclu parlama (sparkle)."""
    pts = []
    for k in range(8):
        a = k * math.pi / 4 - math.pi / 2
        rr = r if k % 2 == 0 else r * 0.22
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=fill)


def seeded(seed):
    return random.Random(seed)


# ------------------------------------------------------------------- sahneler
def sc_aurora(t, pal):
    top, bot, c1, c2, c3 = pal
    img = vgrad(top, bot)
    ribbons = [(0.34, c1, 0.0), (0.46, c2, 0.33), (0.58, c3, 0.66)]
    for base, col, ph in ribbons:
        def draw(d, base=base, col=col, ph=ph):
            up, dn = [], []
            for x in range(-16, C + 24, 8):
                yc = C * base + C * 0.07 * math.sin(TAU * (x / C * 1.25 + t + ph))
                th = C * (0.075 + 0.035 * math.sin(TAU * (x / C * 2.0 + 2 * t + ph)))
                up.append((x, yc - th))
                dn.append((x, yc + th))
            d.polygon(up + dn[::-1], fill=col + (140,))
        glow(img, draw, 22)
    rng = seeded(7)
    d = ImageDraw.Draw(img)
    for i in range(26):
        x, y = rng.random() * C, rng.random() * C * 0.55
        tw = 0.5 + 0.5 * math.sin(TAU * (t * (1 + i % 2) + rng.random()))
        circle(d, x, y, 1.1 * SS * (0.5 + tw), (255, 255, 255, int(70 + 150 * tw)))
    return img


def sc_gold(t, pal=None):
    """Altin saten: akan kumas seritleri, ince parlak kenarlar."""
    img = vgrad((0x1B, 0x11, 0x08), (0x4A, 0x2C, 0x0E))
    tones = [(0x6B, 0x42, 0x14), (0x9A, 0x63, 0x1E), (0xC8, 0x8E, 0x2C), (0xE8, 0xB8, 0x4A),
             (0xF6, 0xD8, 0x86), (0xE8, 0xB8, 0x4A), (0xC8, 0x8E, 0x2C)]
    for k, col in enumerate(tones):
        base = 0.16 + 0.11 * k
        pts_top, pts_bot = [], []
        for x in range(-16, C + 24, 8):
            yc = C * base + C * 0.07 * math.sin(TAU * (x / C * 0.9 + t + k * 0.11)) + C * 0.03 * math.sin(TAU * (x / C * 1.8 - 2 * t + k))
            th = C * (0.075 + 0.02 * math.sin(TAU * (x / C * 1.3 + t + k)))
            pts_top.append((x, yc - th))
            pts_bot.append((x, yc + th))
        lay = layer()
        d = ImageDraw.Draw(lay)
        d.polygon(pts_top + pts_bot[::-1], fill=col + (235,))
        lay = lay.filter(ImageFilter.GaussianBlur(SS * 1.2))
        img.alpha_composite(lay)
        # ust kenarda ince parlak cizgi
        d2 = ImageDraw.Draw(img)
        d2.line(pts_top, fill=lerp(col, (255, 246, 214), 0.6) + (150,), width=SS)
    return img


def sc_neon(t, pal):
    bg, a, b = pal
    img = vgrad(bg, lerp(bg, (0, 0, 0), 0.5))
    cx = cy = C / 2
    r = C * 0.30
    segs = 90
    def ring(d):
        for k in range(segs):
            f = k / segs
            col = lerp(a, b, 0.5 + 0.5 * math.sin(TAU * (f + t)))
            a0 = f * 360 - 90
            d.arc([cx - r, cy - r, cx + r, cy + r], a0, a0 + 360 / segs + 1.5, fill=col + (255,), width=int(C * 0.05))
    glow(img, ring, 18)
    d = ImageDraw.Draw(img)
    for k in range(segs):
        f = k / segs
        col = lerp(a, b, 0.5 + 0.5 * math.sin(TAU * (f + t)))
        a0 = f * 360 - 90
        d.arc([cx - r, cy - r, cx + r, cy + r], a0, a0 + 360 / segs + 1.5, fill=col + (255,), width=int(C * 0.024))
    pul = 0.5 + 0.5 * math.sin(TAU * t)
    glow(img, lambda dd: circle(dd, cx, cy, C * (0.06 + 0.02 * pul), lerp(a, b, 0.5) + (230,)), 14)
    circle(d, cx, cy, C * 0.03, (255, 255, 255, 255))
    # orbit eden parlak nokta
    ang = TAU * t
    ox, oy = cx + r * math.cos(ang), cy + r * math.sin(ang)
    glow(img, lambda dd: circle(dd, ox, oy, C * 0.03, (255, 255, 255, 255)), 10)
    circle(d, ox, oy, C * 0.014, (255, 255, 255, 255))
    return img


def sc_orb(t, pal):
    bg1, bg2, c1, c2 = pal
    img = vgrad(bg1, bg2)
    cx, cy, r = C / 2, C * 0.47, C * 0.31
    # golge
    glow(img, lambda d: d.ellipse([cx - r * 0.8, cy + r * 1.05, cx + r * 0.8, cy + r * 1.22], fill=(0, 0, 0, 120)), 12)
    orb = rgrad(cx - r * 0.25, cy - r * 0.3, r * 1.45, lerp(c1, (255, 255, 255), 0.35), lerp(c2, (0, 0, 0), 0.35))
    m = Image.new("L", (C, C), 0)
    ImageDraw.Draw(m).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(1))
    orb.putalpha(m)
    img.alpha_composite(orb)
    # ici dolasan renkli sis
    fog = layer()
    fd = ImageDraw.Draw(fog)
    for k in range(3):
        a = TAU * (t + k / 3)
        fx = cx + r * 0.45 * math.cos(a)
        fy = cy + r * 0.45 * math.sin(a * 1.0 + k)
        circle(fd, fx, fy, r * 0.42, [c1, (255, 255, 255), c2][k] + (110,))
    fog = fog.filter(ImageFilter.GaussianBlur(C * 0.05))
    fog.putalpha(ImageChops.multiply(fog.getchannel("A"), m))
    img.alpha_composite(fog)
    # kenar isigi + speküler
    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 60), width=int(SS * 1.5))
    glow(img, lambda dd: dd.ellipse([cx - r * 0.62, cy - r * 0.78, cx - r * 0.12, cy - r * 0.42], fill=(255, 255, 255, 190)), 5)
    return img


def sc_constellation(t, pal):
    top, bot, col = pal
    img = vgrad(top, bot)
    rng = seeded(11)
    pts = []
    for i in range(15):
        a, rr = rng.random() * TAU, C * (0.10 + 0.34 * rng.random())
        pts.append((a, rr))
    ang = TAU * t * 0.0 + 0  # tum takimyildiz yavasca doner
    rot = TAU * t
    xy = [(C / 2 + rr * math.cos(a + rot * 0.5), C / 2 + rr * math.sin(a + rot * 0.5)) for a, rr in pts]
    d = ImageDraw.Draw(img)
    for i in range(len(xy)):
        best = sorted(range(len(xy)), key=lambda j: (xy[i][0] - xy[j][0]) ** 2 + (xy[i][1] - xy[j][1]) ** 2)[1:3]
        for j in best:
            d.line([xy[i], xy[j]], fill=col + (70,), width=SS)
    for i, (x, y) in enumerate(xy):
        tw = 0.5 + 0.5 * math.sin(TAU * (t + i / 7.0))
        glow(img, lambda dd, x=x, y=y, tw=tw: circle(dd, x, y, C * 0.02 * (0.7 + tw), col + (200,)), 8)
        circle(d, x, y, SS * (1.6 + 1.4 * tw), (255, 255, 255, 255))
    return img


def sc_ripples(t, pal):
    bg1, bg2, c1, c2 = pal
    img = vgrad(bg1, bg2)
    cx = cy = C / 2
    d = ImageDraw.Draw(img)
    for k in range(4):
        f = (t + k / 4) % 1.0
        r = C * (0.06 + 0.40 * f)
        a = int(210 * (1 - f) ** 1.5)
        col = lerp(c1, c2, f)
        glow(img, lambda dd, r=r, a=a, col=col: dd.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col + (a // 2,), width=int(C * 0.05)), 8)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col + (a,), width=int(C * 0.012))
    glow(img, lambda dd: circle(dd, cx, cy, C * 0.10, c1 + (170,)), 14)
    pearl = rgrad(cx - C * 0.02, cy - C * 0.03, C * 0.12, (255, 255, 255), lerp(c1, (255, 235, 225), 0.4))
    pm = Image.new("L", (C, C), 0)
    ImageDraw.Draw(pm).ellipse([cx - C * 0.07, cy - C * 0.07, cx + C * 0.07, cy + C * 0.07], fill=255)
    pearl.putalpha(pm)
    img.alpha_composite(pearl)
    return img


def sc_bokeh(t, pal):
    top, bot, c1, c2 = pal
    img = vgrad(top, bot)
    rng = seeded(21)
    for i in range(14):
        x0, y0 = rng.random() * C, rng.random() * C
        r = C * (0.05 + 0.10 * rng.random())
        sp = 1 + (i % 3)
        y = (y0 - C * t * (0.5 + sp * 0.5)) % (C + 2 * r) - r
        col = lerp(c1, c2, rng.random())
        a = int(70 + 90 * rng.random())
        glow(img, lambda dd, x=x0 + 10 * math.sin(TAU * (t + i / 5.0)), y=y, r=r, col=col, a=a: circle(dd, x, y, r, col + (a,)), 5)
    return img


def sc_prism(t, pal):
    bg = pal[0]
    img = vgrad(bg, lerp(bg, (0, 0, 0), 0.6))
    cx = cy = C / 2
    r = C * 0.36
    disc = layer()
    dd = ImageDraw.Draw(disc)
    n = 72
    for k in range(n):
        f = k / n
        col = hsv(f + t, 0.55, 1.0)
        dd.pieslice([cx - r, cy - r, cx + r, cy + r], f * 360 - 90, f * 360 - 90 + 360 / n + 1, fill=col + (255,))
    disc = disc.filter(ImageFilter.GaussianBlur(C * 0.02))
    m = Image.new("L", (C, C), 0)
    ImageDraw.Draw(m).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(1))
    disc.putalpha(m)
    glow(img, lambda d: d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=hsv(t, 0.5, 1.0) + (90,)), 30)
    img.alpha_composite(disc)
    # cam gibi ic parlama + gezen serit
    shine = layer()
    sd = ImageDraw.Draw(shine)
    x0 = C * (-0.2 + 1.4 * t)
    sd.polygon([(x0, 0), (x0 + C * 0.10, 0), (x0 - C * 0.10, C), (x0 - C * 0.20, C)], fill=(255, 255, 255, 110))
    shine = shine.filter(ImageFilter.GaussianBlur(C * 0.015))
    shine.putalpha(ImageChops.multiply(shine.getchannel("A"), m))
    img.alpha_composite(shine)
    ImageDraw.Draw(img).ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 90), width=int(SS * 1.4))
    glow(img, lambda d: circle(d, cx - r * 0.42, cy - r * 0.5, r * 0.16, (255, 255, 255, 170)), 6)
    return img


def sc_lava(t, pal):
    top, bot, c1, c2 = pal
    img = vgrad(top, bot)
    m = Image.new("L", (C, C), 0)
    d = ImageDraw.Draw(m)
    for k in range(7):
        a = TAU * (t * (1 if k % 2 == 0 else -1) + k / 7)
        cx = C * (0.5 + 0.24 * math.sin(a + k))
        cy = C * (0.5 + 0.34 * math.cos(a * 1.0 + k * 1.3))
        r = C * (0.13 + 0.06 * (k % 3))
        circle(d, cx, cy, r, 255)
    m = m.filter(ImageFilter.GaussianBlur(C * 0.045)).point(lambda v: 0 if v < 105 else min(255, (v - 105) * 5))
    m = m.filter(ImageFilter.GaussianBlur(1.2))
    fill = vgrad(c1, c2)
    fill.putalpha(m)
    img.alpha_composite(fill)
    # ic parlama
    hi = m.filter(ImageFilter.GaussianBlur(C * 0.03)).point(lambda v: max(0, v - 150))
    hl = Image.new("RGBA", (C, C), (255, 255, 255, 0))
    hl.putalpha(hi.point(lambda v: min(90, v)))
    img.alpha_composite(hl)
    return img


def _petal(cx, cy, ang, r0, r1, half, steps=14):
    """Sivri uclu yaprak (vesica) - merkezden disa dogru."""
    ux, uy = math.cos(ang), math.sin(ang)
    nx, ny = -uy, ux
    left, right = [], []
    for i in range(steps + 1):
        s_ = i / steps
        r = r0 + (r1 - r0) * s_
        w = half * math.sin(math.pi * s_) ** 0.85
        left.append((cx + ux * r + nx * w, cy + uy * r + ny * w))
        right.append((cx + ux * r - nx * w, cy + uy * r - ny * w))
    return left + right[::-1]


def sc_mandala(t, pal):
    bg1, bg2, gold, gem = pal
    img = vgrad(bg1, bg2)
    cx = cy = C / 2
    for n, r0, r1, half, dirn, alpha in [(12, 0.13, 0.44, 0.075, 1, 40), (12, 0.10, 0.34, 0.06, -1, 60), (8, 0.06, 0.22, 0.05, 1, 90)]:
        for k in range(n):
            a = TAU * (k / n + dirn * t / n)
            pts = _petal(cx, cy, a, C * r0, C * r1, C * half)
            lay = layer()
            d = ImageDraw.Draw(lay)
            d.polygon(pts, fill=gold + (alpha,))
            d.line(pts + [pts[0]], fill=gold + (235,), width=int(SS * 1.5))
            img.alpha_composite(lay)
    glow(img, lambda dd: circle(dd, cx, cy, C * 0.08, gem + (200,)), 12)
    d = ImageDraw.Draw(img)
    circle(d, cx, cy, C * 0.045, gem + (255,))
    circle(d, cx - C * 0.012, cy - C * 0.014, C * 0.014, (255, 255, 255, 220))
    d.ellipse([cx - C * 0.06, cy - C * 0.06, cx + C * 0.06, cy + C * 0.06], outline=gold + (255,), width=int(SS * 2))
    return img


def sc_sunset(t, pal):
    sky1, sky2, sun, w1, w2, w3 = pal
    img = vgrad(sky1, sky2)
    cx, cy = C / 2, C * 0.52
    glow(img, lambda d: circle(d, cx, cy, C * 0.26, sun + (110,)), 24)
    sunimg = rgrad(cx, cy, C * 0.20, lerp(sun, (255, 255, 255), 0.4), sun)
    sm = Image.new("L", (C, C), 0)
    ImageDraw.Draw(sm).ellipse([cx - C * 0.17, cy - C * 0.17, cx + C * 0.17, cy + C * 0.17], fill=255)
    sunimg.putalpha(sm)
    img.alpha_composite(sunimg)
    d = ImageDraw.Draw(img)
    for k, (col, base, amp, sp) in enumerate([(w1, 0.60, 0.030, 1), (w2, 0.70, 0.038, -1), (w3, 0.80, 0.045, 1)]):
        pts = [(0, C)]
        for x in range(0, C + 8, 8):
            y = C * base + C * amp * math.sin(TAU * (x / C * (1.5 + k * 0.5) + sp * t))
            pts.append((x, y))
        pts.append((C, C))
        d.polygon(pts, fill=col + (255,))
    return img


def sc_galaxy(t, pal):
    bg, c1, c2 = pal
    img = vgrad(bg, lerp(bg, (0, 0, 0), 0.65))
    cx = cy = C / 2
    glow(img, lambda d: circle(d, cx, cy, C * 0.13, c1 + (150,)), 22)
    rng = seeded(31)
    d = ImageDraw.Draw(img)
    for arm in range(2):
        for i in range(230):
            f = i / 230.0
            r = C * (0.03 + 0.42 * f ** 0.9)
            a = arm * math.pi + 3.6 * f * math.pi + TAU * t
            jx, jy = rng.gauss(0, C * 0.012 * (0.4 + f)), rng.gauss(0, C * 0.012 * (0.4 + f))
            x, y = cx + r * math.cos(a) + jx, cy + r * math.sin(a) + jy
            col = lerp(c1, c2, f)
            br = int(255 * (0.95 - 0.55 * f))
            circle(d, x, y, SS * (0.9 + 1.3 * (1 - f) * rng.random()), (min(255, col[0] + 40), min(255, col[1] + 40), min(255, col[2] + 40), br))
    circle(d, cx, cy, C * 0.03, (255, 246, 222, 255))
    return img


# ------------------------------------------------- soyut avatarlar (56-67)
ABSTRACT = [
    lambda t: sc_aurora(t, ((0x08, 0x12, 0x2C), (0x0D, 0x2B, 0x3E), (0x4A, 0xE8, 0xB0), (0x5B, 0x8B, 0xFF), (0xB0, 0x5B, 0xFF))),
    lambda t: sc_gold(t),
    lambda t: sc_neon(t, ((0x0B, 0x0B, 0x22), (0xFF, 0x3D, 0xB8), (0x3D, 0xE3, 0xFF))),
    lambda t: sc_orb(t, ((0x2B, 0x1B, 0x5A), (0x0E, 0x0B, 0x24), (0x8B, 0xC6, 0xFF), (0x7A, 0x4A, 0xE8))),
    lambda t: sc_constellation(t, ((0x0A, 0x10, 0x30), (0x1E, 0x1B, 0x4B), (0xB8, 0xD4, 0xFF))),
    lambda t: sc_ripples(t, ((0x3A, 0x14, 0x22), (0x1B, 0x0A, 0x14), (0xF2, 0xA6, 0x8C), (0xFF, 0xD3, 0xB6))),
    lambda t: sc_bokeh(t, ((0x2A, 0x14, 0x30), (0x0F, 0x0B, 0x1E), (0xFF, 0xB4, 0x6B), (0xFF, 0x6B, 0xB0))),
    lambda t: sc_prism(t, ((0x11, 0x12, 0x26),)),
    lambda t: sc_lava(t, ((0x2A, 0x0A, 0x2E), (0x14, 0x06, 0x1E), (0xFF, 0x9A, 0x3D), (0xFF, 0x3D, 0x8B))),
    lambda t: sc_mandala(t, ((0x14, 0x1A, 0x3D), (0x0A, 0x0D, 0x22), (0xF0, 0xC8, 0x6A), (0xE0, 0x4A, 0x6E))),
    lambda t: sc_sunset(t, ((0x3B, 0x1F, 0x6B), (0xFF, 0x8A, 0x5C), (0xFF, 0xD8, 0x6B), (0xA0, 0x3A, 0x7A), (0x5E, 0x2A, 0x78), (0x2E, 0x1B, 0x55))),
    lambda t: sc_galaxy(t, ((0x08, 0x08, 0x22), (0x9B, 0x8B, 0xFF), (0x5B, 0xD4, 0xFF))),
]

# ------------------------------------------- portre sahneleri (68-79, 12 adet)
PORTRAIT_SCENES = [
    lambda t: sc_constellation(t, ((0x0A, 0x10, 0x30), (0x26, 0x2A, 0x5E), (0xB8, 0xD4, 0xFF))),
    lambda t: sc_sunset(t, ((0x3B, 0x1F, 0x6B), (0xFF, 0x8A, 0x5C), (0xFF, 0xD8, 0x6B), (0xA0, 0x3A, 0x7A), (0x5E, 0x2A, 0x78), (0x2E, 0x1B, 0x55))),
    lambda t: sc_aurora(t, ((0x08, 0x12, 0x2C), (0x0D, 0x2B, 0x3E), (0x4A, 0xE8, 0xB0), (0x5B, 0x8B, 0xFF), (0xB0, 0x5B, 0xFF))),
    lambda t: sc_bokeh(t, ((0x3A, 0x26, 0x0C), (0x18, 0x10, 0x08), (0xFF, 0xD3, 0x6B), (0xFF, 0x9B, 0x3D))),
    lambda t: sc_ripples(t, ((0x0B, 0x24, 0x44), (0x06, 0x10, 0x26), (0x3D, 0xE3, 0xFF), (0x9B, 0x8B, 0xFF))),
    lambda t: sc_lava(t, ((0x1F, 0x0B, 0x33), (0x0E, 0x06, 0x1E), (0xFF, 0x7A, 0xB8), (0xFF, 0xB4, 0x6B))),
    lambda t: sc_bokeh(t, ((0x2A, 0x1A, 0x2E), (0x10, 0x0C, 0x18), (0xF6, 0xD8, 0xA6), (0xE8, 0xA6, 0xC8))),
    lambda t: sc_lava(t, ((0x33, 0x14, 0x05), (0x1A, 0x08, 0x02), (0xFF, 0x9A, 0x3D), (0xFF, 0x5B, 0x3D))),
    lambda t: sc_prism(t, ((0x14, 0x16, 0x2C),)),
    lambda t: sc_aurora(t, ((0x1B, 0x0A, 0x2E), (0x2E, 0x10, 0x3E), (0xFF, 0x7A, 0xC8), (0x7A, 0xE8, 0xB0), (0xFF, 0xD3, 0x6B))),
    lambda t: sc_galaxy(t, ((0x0F, 0x08, 0x26), (0xFF, 0x8A, 0xD4), (0x8B, 0x8B, 0xFF))),
    lambda t: sc_ripples(t, ((0x0A, 0x30, 0x3A), (0x05, 0x12, 0x1E), (0x5B, 0xFF, 0xD4), (0x3D, 0xA6, 0xFF))),
    lambda t: sc_constellation(t, ((0x1B, 0x0A, 0x33), (0x3A, 0x1B, 0x5E), (0xFF, 0xC8, 0xF0))),
]


def portrait_sparkles(img, t, seed):
    """Parlamalar yalnizca kadrajin kose/kenarlarinda (yuzun ustune gelmez)."""
    rng = seeded(seed)
    d = ImageDraw.Draw(img)
    spots = [(0.10, 0.12), (0.90, 0.10), (0.06, 0.42), (0.94, 0.40), (0.20, 0.05), (0.80, 0.04), (0.08, 0.66), (0.93, 0.62)]
    for i, (fx, fy) in enumerate(spots):
        x, y = C * (fx + 0.02 * rng.random()), C * (fy + 0.02 * rng.random())
        ph = rng.random()
        tw = max(0.0, math.sin(TAU * (t * (1 + i % 2) + ph)))
        if tw > 0.05:
            r = C * (0.014 + 0.022 * tw) * (1 + (i % 3) * 0.25)
            glow(img, lambda dd, x=x, y=y, r=r: star4(dd, x, y, r * 1.6, (255, 255, 255, 110)), 4)
            star4(d, x, y, r, (255, 255, 255, int(120 + 135 * tw)))


# ------------------------------------------------------------------ cikti
def save_gif(frames, path, colors, dither=False):
    small = [f.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS) for f in frames]
    step = max(1, len(small) // 8)
    sample = small[::step][:8]
    mosaic = Image.new("RGB", (SIZE * 4, SIZE * 2))
    for i, im in enumerate(sample):
        mosaic.paste(im, ((i % 4) * SIZE, (i // 4) * SIZE))
    pal = mosaic.quantize(colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    mode = Image.Dither.FLOYDSTEINBERG if dither else Image.Dither.NONE
    q = [im.quantize(palette=pal, dither=mode) for im in small]
    q[0].save(path, save_all=True, append_images=q[1:], duration=MS, loop=0,
              optimize=False, disposal=1)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    only = set(int(a) for a in sys.argv[1:])
    total = 0
    index = FIRST_INDEX
    for fn in ABSTRACT:
        if only and index not in only:
            index += 1
            continue
        frames = [fn(k / N) for k in range(N)]
        out = os.path.join(OUT_DIR, "avatar_anim_%02d.gif" % index)
        save_gif(frames, out, 144)
        total += os.path.getsize(out)
        print("%s %5.0f KB" % (os.path.basename(out), os.path.getsize(out) / 1024))
        index += 1

    portraits = sorted(glob.glob(os.path.join(FRAMES_DIR, "p*")))
    if not portraits:
        print("Portre kareleri yok (bkz. dosya basi); yalniz soyut avatarlar uretildi.")
    for pi, pdir in enumerate(portraits):
        if only and index not in only:
            index += 1
            continue
        scene = PORTRAIT_SCENES[pi % len(PORTRAIT_SCENES)]
        files = sorted(glob.glob(os.path.join(pdir, "f*.png")))
        frames = []
        for k, f in enumerate(files):
            t = k / len(files)
            bg = scene(t)
            av = Image.open(f).convert("RGBA").resize((C, C), Image.LANCZOS)
            # portreyi hafifce kucultup alta oturt: baslik ve omuzlar bosluk birakmasin
            bg.alpha_composite(av)
            portrait_sparkles(bg, t, 100 + pi)
            frames.append(bg)
        out = os.path.join(OUT_DIR, "avatar_anim_%02d.gif" % index)
        save_gif(frames, out, 208)
        total += os.path.getsize(out)
        print("%s %5.0f KB" % (os.path.basename(out), os.path.getsize(out) / 1024))
        index += 1
    print("son index: %d, bu kosuda %.2f MB" % (index - 1, total / 1024 / 1024))


if __name__ == "__main__":
    main()
