#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Klasik hazir avatarlar (20 adet) - modern, yumusak golgeli duz illustrasyon.

Kullanim:
    python scripts/generate_classic_avatars.py

Cikti: assets/avatars/avatar_01.png ... avatar_20.png (320 px RGB)

STIL: 2020'lerin "flat + soft gradient" illustrasyonu - buyuk yuvarlak
formlar, iki tonlu sac, allik, gozde tek parlama noktasi, arka planda buyuk
yari saydam daireler ve yumusak zemin gradyani. Onceki set duz ve kucuk
detaysizdi.

APPEND-ONLY: dosya adlari kullanicilarin sectigi avatar_url'ye bagli;
AVATARS listesinin sirasi (kavramlar) degistirilmez, yenisi sona eklenir.
Gorunumu iyilestirmek serbest (ayni kavram = ayni indeks).
"""

import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 320
SS = 4
C = S * SS

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "avatars")


# ------------------------------------------------------------------ yardimci
def mix(a, b, f):
    f = max(0.0, min(1.0, f))
    return tuple(int(round(a[i] + (b[i] - a[i]) * f)) for i in range(3))


def darker(c, f=0.2):
    return mix(c, (20, 12, 20), f)


def lighter(c, f=0.2):
    return mix(c, (255, 250, 245), f)


def P(pts):
    return [(x * SS, y * SS) for x, y in pts]


def spline(points, closed=True, steps=12):
    n = len(points)
    out = []
    span = range(n) if closed else range(n - 1)
    for i in span:
        p0 = points[(i - 1) % n] if closed else points[max(i - 1, 0)]
        p1 = points[i % n]
        p2 = points[(i + 1) % n]
        p3 = points[(i + 2) % n] if closed else points[min(i + 2, n - 1)]
        for k in range(steps):
            t = k / steps
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    if not closed:
        out.append(points[-1])
    return out


class Art:
    """Tek bir avatarin tuvali: maske + gradyan tabanli cizim yardimcilari."""

    def __init__(self):
        self.img = Image.new("RGBA", (C, C), (0, 0, 0, 0))

    # -- temel
    def mask(self, fn, blur=0):
        m = Image.new("L", (C, C), 0)
        fn(ImageDraw.Draw(m))
        if blur:
            m = m.filter(ImageFilter.GaussianBlur(blur * SS))
        return m

    def paint(self, m, color, alpha=1.0):
        if alpha < 1.0:
            m = m.point(lambda v: int(v * alpha))
        lay = Image.new("RGBA", (C, C), color + (0,))
        lay.putalpha(m)
        self.img.alpha_composite(lay)

    def grad_paint(self, m, c1, c2, angle=90):
        """Maskeyi dogrusal gradyanla boya (angle: 90 = ustten alta)."""
        g = Image.linear_gradient("L").resize((C, C), Image.BILINEAR)
        g = g.rotate(angle - 90, resample=Image.BILINEAR, expand=False, fillcolor=128)
        fill = Image.composite(Image.new("RGB", (C, C), c2), Image.new("RGB", (C, C), c1), g).convert("RGBA")
        fill.putalpha(m)
        self.img.alpha_composite(fill)

    def poly(self, pts, color, alpha=1.0, smooth=True, closed=True, blur=0):
        p = P(spline(pts, closed=closed)) if smooth else P(pts)
        m = self.mask(lambda d: d.polygon(p, fill=255), blur)
        self.paint(m, color, alpha)
        return m

    def poly_grad(self, pts, c1, c2, angle=90, smooth=True):
        p = P(spline(pts)) if smooth else P(pts)
        m = self.mask(lambda d: d.polygon(p, fill=255))
        self.grad_paint(m, c1, c2, angle)
        return m

    def ellipse(self, cx, cy, rx, ry, color, alpha=1.0, blur=0):
        m = self.mask(lambda d: d.ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=255), blur)
        self.paint(m, color, alpha)
        return m

    def ellipse_grad(self, cx, cy, rx, ry, c1, c2, angle=90):
        m = self.mask(lambda d: d.ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=255))
        self.grad_paint(m, c1, c2, angle)
        return m

    def stroke(self, pts, color, width, alpha=1.0, smooth=True):
        p = P(spline(pts, closed=False)) if smooth else P(pts)

        def fn(d):
            d.line(p, fill=255, width=int(width * SS), joint="curve")
            r = width * SS / 2
            for x, y in (p[0], p[-1]):
                d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        self.paint(self.mask(fn), color, alpha)

    def clipped(self, clip_mask, fn):
        """fn(Art) ile bir alt-katman ciz, clip_mask ile kirp, bindir."""
        sub = Art()
        fn(sub)
        a = ImageChops.multiply(sub.img.getchannel("A"), clip_mask)
        sub.img.putalpha(a)
        self.img.alpha_composite(sub.img)


# ------------------------------------------------------------------ sahneler
def background(a, c1, c2):
    g = Image.linear_gradient("L").resize((C, C), Image.BILINEAR).rotate(45, resample=Image.BILINEAR, fillcolor=128)
    bg = Image.composite(Image.new("RGB", (C, C), c2), Image.new("RGB", (C, C), c1), g).convert("RGBA")
    a.img.alpha_composite(bg)
    # buyuk yari saydam daireler: derinlik
    a.ellipse(250, 60, 120, 120, lighter(c1, 0.5), 0.22)
    a.ellipse(40, 300, 150, 130, darker(c2, 0.25), 0.22)
    a.ellipse(300, 260, 60, 60, lighter(c2, 0.4), 0.18)


def body(a, cloth, skin, style="crew"):
    sh = [(20, 330), (28, 292), (70, 262), (120, 250), (160, 246), (200, 250), (250, 262), (292, 292), (300, 330)]
    m = a.poly_grad(sh, lighter(cloth, 0.14), darker(cloth, 0.16), 90)
    # omuz golgesi + gogus isigi
    a.clipped(m, lambda s: (s.ellipse(40, 330, 60, 60, darker(cloth, 0.4), 0.35, blur=10),
                            s.ellipse(280, 330, 60, 60, darker(cloth, 0.4), 0.35, blur=10),
                            s.ellipse(160, 300, 70, 30, lighter(cloth, 0.35), 0.30, blur=12)))
    # boyun
    neck = [(138, 190), (182, 190), (184, 236), (176, 252), (144, 252), (136, 236)]
    nm = a.poly(neck, mix(skin, (150, 90, 70), 0.20))
    a.clipped(nm, lambda s: s.ellipse(160, 196, 44, 26, darker(skin, 0.55), 0.55, blur=8))
    # yaka
    if style == "crew":
        a.poly([(126, 249), (160, 274), (194, 249), (184, 244), (160, 258), (136, 244)], darker(cloth, 0.28))
    elif style == "vneck":
        a.poly([(130, 248), (160, 292), (190, 248), (180, 243), (160, 272), (140, 243)], darker(cloth, 0.28))
    elif style == "hood":
        a.poly([(120, 246), (160, 268), (200, 246), (212, 238), (160, 252), (108, 238)], darker(cloth, 0.22))
        a.stroke([(146, 262), (144, 296)], lighter(cloth, 0.7), 4)
        a.stroke([(174, 262), (176, 296)], lighter(cloth, 0.7), 4)


HEAD = [(160, 74), (198, 82), (216, 114), (218, 150), (208, 186), (186, 208), (160, 216),
        (134, 208), (112, 186), (102, 150), (104, 114), (122, 82)]


def head(a, skin, ears=True):
    if ears:
        for sx in (-1, 1):
            a.ellipse(160 + sx * 57, 154, 11, 15, mix(skin, (200, 120, 100), 0.10))
            a.ellipse(160 + sx * 57, 155, 5, 8, darker(skin, 0.14), 0.7)
    m = a.poly_grad(HEAD, lighter(skin, 0.20), darker(skin, 0.10), 60)
    a.clipped(m, lambda s: (
        s.ellipse(160, 214, 56, 22, darker(skin, 0.5), 0.35, blur=9),
        s.ellipse(112, 150, 26, 60, darker(skin, 0.35), 0.28, blur=12),
        s.ellipse(208, 150, 26, 60, darker(skin, 0.45), 0.32, blur=12)))
    return m


def face(a, skin, eye, brow, female=False, smile=1.0, lashes=False, eye_style="oval", freckles=False, blush=True):
    ey = 152
    for sx in (-1, 1):
        x = 160 + sx * 30
        if eye_style == "oval":
            a.ellipse(x, ey, 7.2, 9.5, (32, 22, 26))
            a.ellipse(x - 2.2, ey - 3.2, 2.6, 2.6, (255, 255, 255), 0.95)
            a.ellipse(x + 2.4, ey + 3.0, 1.2, 1.2, (255, 255, 255), 0.6)
        else:  # mutlu kapali goz
            a.stroke([(x - 8, ey + 2), (x, ey - 7), (x + 8, ey + 2)], (32, 22, 26), 3.6)
        if lashes:
            a.stroke([(x - 9, ey - 5), (x - 7, ey - 9)] if sx < 0 else [(x + 9, ey - 5), (x + 7, ey - 9)], (32, 22, 26), 2.4)
            a.stroke([(x - 8, ey - 8), (x + 8, ey - 8)], (32, 22, 26), 1.6, 0.0) if False else None
        # kas
        by = ey - 20
        a.stroke([(x - 11, by + 3), (x, by - 2 * (1 if not female else 1.4)), (x + 11, by + 2)], brow, 4.6 if not female else 3.4)
    # burun
    a.stroke([(160, 160), (156, 176), (163, 178)], darker(skin, 0.28), 3.0, 0.75)
    # agiz
    if smile > 0.8:
        mouth = [(140, 189), (150, 196), (160, 198), (170, 196), (180, 189), (174, 203), (160, 210), (146, 203)]
        m = a.poly(mouth, (118, 42, 54))
        # Ust disler: agiz konturunun hemen altinda ince bir bant (koselerde sivri "diş" olmasin).
        a.clipped(m, lambda s_: (s_.ellipse(160, 207, 14, 6, (238, 120, 132), 0.9),
                                 s_.poly([(140, 189), (150, 196), (160, 198), (170, 196), (180, 189), (176, 191), (170, 197.5), (160, 200), (150, 197.5), (144, 191)], (252, 248, 244), smooth=False)))
    else:
        a.stroke([(146, 194), (160, 202), (174, 194)], (140, 60, 70), 4.0)
    if blush:
        for sx in (-1, 1):
            a.ellipse(160 + sx * 44, 174, 15, 9, (236, 110, 118), 0.36 if female else 0.22, blur=5)
    if freckles:
        import random
        rng = random.Random(4)
        for sx in (-1, 1):
            for _ in range(7):
                a.ellipse(160 + sx * (26 + rng.random() * 26), 166 + rng.random() * 12, 1.7, 1.7, darker(skin, 0.5), 0.6)


# ----------------------------------------------------------------- sac stilleri
def hair_common(a, m, col):
    """Ust yarida yumusak parlama + alt yarida golge."""
    a.clipped(m, lambda s: (s.ellipse(140, 92, 44, 16, lighter(col, 0.55), 0.42, blur=8),
                            s.ellipse(200, 130, 24, 46, darker(col, 0.5), 0.35, blur=10)))


def hair_bangs(a, col, side=1):
    back = [(96, 130), (100, 96), (126, 72), (160, 64), (196, 72), (220, 96), (224, 130), (214, 118), (110, 118)]
    a.poly(back, darker(col, 0.12))
    front = [(102, 132), (100, 100), (124, 76), (160, 68), (196, 76), (220, 100), (218, 132), (206, 112),
             (176, 104), (150, 118), (130, 112), (112, 122)]
    m = a.poly(front, col)
    hair_common(a, m, col)


def hair_bun(a, col, bun_col=None, y=58):
    bc = bun_col or col
    a.ellipse(160, y, 28, 26, darker(bc, 0.1))
    a.ellipse(154, y - 7, 15, 11, lighter(bc, 0.4), 0.45, blur=4)
    front = [(102, 136), (100, 100), (124, 76), (160, 70), (196, 76), (220, 100), (218, 136), (206, 112),
             (184, 100), (160, 98), (136, 100), (114, 112)]
    m = a.poly(front, col)
    hair_common(a, m, col)


def hair_long_back(a, col):
    back = [(88, 250), (86, 150), (98, 96), (128, 66), (160, 60), (192, 66), (222, 96), (234, 150), (232, 250), (200, 240), (120, 240)]
    a.poly(back, darker(col, 0.22))


def hair_long(a, col, freckles_sideburn=False):
    front = [(104, 200), (100, 130), (108, 96), (130, 74), (160, 66), (190, 74), (212, 96), (220, 130), (216, 200),
             (208, 150), (204, 118), (170, 100), (140, 112), (118, 124), (112, 160)]
    m = a.poly(front, col)
    hair_common(a, m, col)
    # ipeksi seritler
    a.clipped(m, lambda s: (s.stroke([(112, 130), (108, 190)], lighter(col, 0.4), 3, 0.35), s.stroke([(208, 130), (212, 190)], lighter(col, 0.4), 3, 0.35)))


def hair_bob_back(a, col):
    back = [(92, 210), (90, 130), (100, 92), (128, 68), (160, 62), (192, 68), (220, 92), (230, 130), (228, 210), (196, 216), (124, 216)]
    a.poly(back, darker(col, 0.18))


def hair_bob(a, col):
    front = [(100, 200), (96, 128), (108, 92), (130, 72), (160, 66), (190, 72), (212, 92), (224, 128), (220, 200),
             (208, 160), (206, 116), (178, 96), (150, 112), (120, 122), (112, 160)]
    m = a.poly(front, col)
    hair_common(a, m, col)


def hair_curly(a, col, big=True):
    import random
    rng = random.Random(9)
    r0 = 16 if big else 12
    for ring, (cx, cy, rx, ry, n) in enumerate([(160, 108, 66, 50, 18), (160, 100, 54, 40, 14), (160, 96, 40, 30, 9)]):
        for i in range(n):
            ang = math.pi * (1.05 + 0.95 * i / (n - 1))
            x = cx + rx * math.cos(ang)
            y = cy + ry * math.sin(ang) * 1.05
            rr = r0 + rng.random() * 4
            a.ellipse(x, y, rr, rr, [darker(col, 0.15), col, col][ring % 3])
            if ring == 1:
                a.ellipse(x - 4, y - 5, rr * 0.45, rr * 0.4, lighter(col, 0.45), 0.35, blur=1.5)
    # yanlar
    for sx in (-1, 1):
        for k in range(3):
            a.ellipse(160 + sx * (62 - k * 3), 118 + k * 15, 13, 13, col)
    front = [(112, 128), (110, 104), (130, 84), (160, 78), (190, 84), (210, 104), (208, 128), (196, 108), (160, 100), (124, 108)]
    m = a.poly(front, col)
    hair_common(a, m, col)


def hair_ponytail(a, col):
    tail = [(214, 100), (256, 110), (270, 150), (262, 200), (246, 214), (244, 170), (232, 130), (214, 118)]
    a.poly(tail, darker(col, 0.08))
    a.stroke([(238, 118), (254, 160), (250, 200)], lighter(col, 0.4), 3, 0.35)
    a.ellipse(222, 108, 7, 7, (240, 90, 120))
    hair_bangs(a, col)


def hair_none(a, col):
    pass


# ----------------------------------------------------------------- aksesuarlar
def glasses(a, rim=(30, 30, 50), round_=True, tint=(200, 230, 250), tint_a=0.25, sun=False):
    for sx in (-1, 1):
        x = 160 + sx * 30
        if round_:
            box = [(x - 21) * SS, (131) * SS, (x + 21) * SS, (173) * SS]
            m = a.mask(lambda d, b=box: d.ellipse(b, fill=255))
        else:
            box = [(x - 22) * SS, 133 * SS, (x + 22) * SS, 171 * SS]
            m = a.mask(lambda d, b=box: d.rounded_rectangle(b, radius=10 * SS, fill=255))
        a.paint(m, (20, 20, 26) if sun else tint, 0.86 if sun else tint_a)
        a.clipped(m, lambda s, x=x: s.stroke([(x - 14, 170), (x + 6, 134)], (255, 255, 255), 5, 0.22))
        edge = ImageChops.subtract(m, m.filter(ImageFilter.MinFilter(int(3.4 * SS) | 1)))
        a.paint(edge, rim, 1.0)
    a.stroke([(146, 148), (160, 146), (174, 148)] if False else [(150, 146), (160, 143), (170, 146)], rim, 3.2)
    for sx in (-1, 1):
        a.stroke([(160 + sx * 51, 146), (160 + sx * 56, 150)], rim, 2.8)


def beard(a, col, style="full", skin=(200, 150, 120)):
    if style == "full":
        pts = [(108, 158), (112, 196), (132, 222), (160, 232), (188, 222), (208, 196), (212, 158), (204, 176), (190, 192), (170, 186), (160, 190), (150, 186), (130, 192), (116, 176)]
        m = a.poly(pts, col)
        a.clipped(m, lambda s: s.ellipse(160, 236, 60, 20, darker(col, 0.5), 0.45, blur=8))
        # agiz cevresi acik kalsin
        a.poly([(142, 190), (160, 197), (178, 190), (172, 205), (160, 209), (148, 205)], (120, 44, 56))
        a.poly([(145, 191), (160, 197), (175, 191), (170, 195), (160, 200), (150, 195)], (252, 248, 244))
    a.poly([(136, 186), (148, 182), (160, 186), (172, 182), (184, 186), (176, 194), (160, 190), (144, 194)], darker(col, 0.05))


def mustache(a, col):
    a.poly([(132, 184), (146, 178), (160, 184), (174, 178), (188, 184), (180, 194), (160, 188), (140, 194)], col)


def cap(a, col, brim_col=None):
    bc = brim_col or darker(col, 0.15)
    dome = [(100, 118), (102, 86), (126, 62), (160, 56), (194, 62), (218, 86), (220, 118), (160, 112)]
    m = a.poly_grad(dome, lighter(col, 0.15), darker(col, 0.12), 70)
    a.clipped(m, lambda s: s.ellipse(140, 80, 30, 12, lighter(col, 0.6), 0.35, blur=6))
    a.poly([(96, 118), (160, 108), (224, 118), (238, 132), (214, 128), (160, 122), (106, 128), (84, 134)], bc)
    a.ellipse(160, 58, 6, 4, darker(col, 0.25))


def beanie(a, col, band=None, pom=(255, 255, 255)):
    bandc = band or lighter(col, 0.25)
    dome = [(98, 122), (100, 88), (124, 64), (160, 58), (196, 64), (220, 88), (222, 122), (160, 118)]
    m = a.poly_grad(dome, lighter(col, 0.12), darker(col, 0.14), 70)
    a.clipped(m, lambda s: [s.stroke([(160 + k * 14, 60), (160 + k * 17, 118)], darker(col, 0.25), 2.4, 0.5) for k in range(-4, 5)])
    a.poly([(96, 108), (100, 132), (220, 132), (224, 108), (160, 104)], bandc)
    a.clipped(a.mask(lambda d: d.polygon(P([(96, 108), (100, 132), (220, 132), (224, 108), (160, 104)]), fill=255)),
              lambda s: [s.stroke([(96 + k * 12, 106), (96 + k * 12, 134)], darker(bandc, 0.2), 2, 0.6) for k in range(0, 12)])
    a.ellipse(160, 50, 16, 15, pom)
    a.ellipse(155, 45, 6, 5, (255, 255, 255), 0.6, blur=1.5)


def headphones(a, col, pad=None):
    pc = pad or lighter(col, 0.18)
    a.stroke([(100, 150), (100, 96), (130, 66), (160, 60), (190, 66), (220, 96), (220, 150)], col, 9)
    for sx in (-1, 1):
        a.ellipse(160 + sx * 60, 158, 16, 26, darker(col, 0.15))
        a.ellipse(160 + sx * 60, 158, 10, 19, pc)
        a.ellipse(160 + sx * 63, 148, 3, 9, (255, 255, 255), 0.3, blur=2)


def cat_ears(a, col, inner=(240, 150, 170)):
    for sx in (-1, 1):
        a.poly([(160 + sx * 34, 86), (160 + sx * 52, 34), (160 + sx * 74, 84)], col, smooth=False)
        a.poly([(160 + sx * 42, 84), (160 + sx * 52, 52), (160 + sx * 66, 84)], inner, smooth=False)


def hijab(a, col):
    outer = [(160, 52), (206, 62), (232, 100), (238, 160), (240, 230), (214, 262), (160, 270), (106, 262), (80, 230), (82, 160), (88, 100), (114, 62)]
    m = a.poly_grad(outer, lighter(col, 0.18), darker(col, 0.14), 70)
    a.clipped(m, lambda s: (s.ellipse(230, 200, 30, 70, darker(col, 0.5), 0.28, blur=10),
                            s.ellipse(120, 90, 30, 16, lighter(col, 0.6), 0.32, blur=6)))
    return outer


# ------------------------------------------------------------------- robot
def robot(a, cloth):
    metal = (200, 214, 224)
    dark = (44, 60, 76)
    body_m = a.poly_grad([(70, 330), (80, 268), (120, 252), (200, 252), (240, 268), (250, 330)], (170, 186, 200), (110, 128, 146), 90, smooth=False)
    a.ellipse(160, 300, 12, 12, (80, 220, 230), 0.9)
    a.poly([(140, 240), (180, 240), (182, 258), (138, 258)], (130, 146, 160), smooth=False)
    for sx in (-1, 1):
        a.poly([(160 + sx * 96, 140), (160 + sx * 112, 140), (160 + sx * 112, 190), (160 + sx * 96, 190)], (150, 166, 182), smooth=False)
    hm = a.mask(lambda d: d.rounded_rectangle([90 * SS, 86 * SS, 230 * SS, 232 * SS], radius=36 * SS, fill=255))
    a.grad_paint(hm, (226, 236, 244), (150, 168, 184), 60)
    a.clipped(hm, lambda s: (s.ellipse(120, 100, 30, 12, (255, 255, 255), 0.55, blur=6), s.ellipse(210, 220, 50, 26, darker(metal, 0.5), 0.35, blur=10)))
    vm = a.mask(lambda d: d.rounded_rectangle([108 * SS, 126 * SS, 212 * SS, 186 * SS], radius=26 * SS, fill=255))
    a.paint(vm, dark)
    a.clipped(vm, lambda s: s.ellipse(150, 136, 40, 8, (255, 255, 255), 0.18, blur=4))
    for sx in (-1, 1):
        a.ellipse(160 + sx * 26, 156, 11, 13, (84, 222, 236))
        a.ellipse(160 + sx * 26 - 3, 151, 4, 4, (255, 255, 255), 0.9)
    a.stroke([(146, 200), (160, 208), (174, 200)], (84, 222, 236), 5)
    a.stroke([(160, 86), (160, 56)], (150, 166, 182), 6)
    a.ellipse(160, 48, 10, 10, (255, 110, 120))
    a.ellipse(157, 45, 3.5, 3.5, (255, 255, 255), 0.8)


# --------------------------------------------------------------------- katalog
SK = {
    "fair": (250, 214, 190),
    "light": (244, 196, 160),
    "tan": (222, 164, 120),
    "brown": (176, 118, 78),
    "dark": (120, 76, 50),
    "deep": (86, 52, 36),
}

HC = {
    "black": (36, 28, 32), "dkbrown": (74, 46, 34), "brown": (122, 78, 46), "auburn": (150, 60, 42),
    "red": (190, 70, 44), "blonde": (232, 188, 96), "gray": (176, 176, 182), "white": (236, 234, 230),
}

# APPEND-ONLY: sira = dosya numarasi (1..20).
AVATARS = [
    dict(bg=((110, 150, 245), (70, 90, 200)), skin="light", hair=("bangs", "black"), cloth=(64, 82, 170), boy=True, cls="crew", brow="black"),
    dict(bg=((250, 150, 180), (220, 90, 140)), skin="light", hair=("bun", "dkbrown"), cloth=(196, 70, 120), girl=True, cls="vneck", brow="dkbrown", lashes=True),
    dict(bg=((160, 130, 240), (110, 80, 200)), skin="tan", hair=("long", "black"), cloth=(96, 70, 190), girl=True, cls="crew", brow="black", lashes=True),
    dict(bg=((70, 200, 180), (30, 140, 130)), skin="dark", hair=("curly", "black"), cloth=(30, 140, 120), girl=True, cls="crew", brow="black", lashes=True),
    dict(bg=((255, 170, 90), (230, 110, 50)), skin="tan", hair=("none", "black"), cloth=(200, 100, 40), boy=True, cls="hood", brow="dkbrown", beard="dkbrown"),
    dict(bg=((110, 200, 140), (50, 140, 90)), skin="fair", hair=("bangs", "brown"), cloth=(50, 140, 90), boy=True, cls="crew", brow="brown", cap=(220, 60, 70)),
    dict(bg=((110, 120, 220), (70, 70, 170)), skin="light", hair=("bangs", "black"), cloth=(66, 66, 170), boy=True, cls="crew", brow="black", glasses="round"),
    dict(bg=((255, 150, 190), (225, 100, 150)), skin="tan", hair=("none", "black"), cloth=(212, 96, 140), girl=True, cls="crew", brow="dkbrown", lashes=True, hijab=(247, 238, 230)),
    dict(bg=((80, 190, 230), (40, 130, 190)), skin="fair", hair=("bangs", "brown"), cloth=(40, 130, 190), boy=True, cls="crew", brow="brown", beanie=(240, 100, 96)),
    dict(bg=((255, 210, 100), (235, 160, 40)), skin="fair", hair=("ponytail", "blonde"), cloth=(224, 150, 30), girl=True, cls="vneck", brow="brown", lashes=True),
    dict(bg=((150, 210, 90), (90, 160, 40)), skin="deep", hair=("curly", "black"), cloth=(90, 150, 40), boy=True, cls="crew", brow="black", eye_style="happy"),
    dict(bg=((110, 140, 160), (70, 96, 116)), skin="tan", hair=("bangs", "dkbrown"), cloth=(70, 96, 116), boy=True, cls="hood", brow="dkbrown", phones=(255, 120, 70)),
    dict(bg=((200, 120, 240), (150, 70, 200)), skin="fair", hair=("bangs", "dkbrown"), cloth=(150, 70, 190), girl=True, cls="crew", brow="dkbrown", lashes=True, ears=((70, 50, 84), (240, 150, 170))),
    dict(bg=((70, 90, 108), (40, 56, 70)), robot=True),
    dict(bg=((90, 170, 250), (50, 110, 210)), skin="light", hair=("bob", "gray"), cloth=(46, 110, 200), girl=True, cls="vneck", brow="gray", glasses="round", old=True),
    dict(bg=((240, 140, 110), (210, 90, 70)), skin="tan", hair=("bangs", "dkbrown"), cloth=(190, 90, 70), boy=True, cls="crew", brow="dkbrown", mustache="dkbrown"),
    dict(bg=((80, 180, 130), (40, 130, 90)), skin="brown", hair=("bob", "black"), cloth=(40, 130, 90), girl=True, cls="crew", brow="black", lashes=True),
    dict(bg=((160, 100, 240), (120, 60, 200)), skin="fair", hair=("bun", "red"), cloth=(120, 64, 200), girl=True, cls="vneck", brow="red", lashes=True, glasses="round_red", freckles=True),
    dict(bg=((40, 190, 190), (20, 140, 150)), skin="tan", hair=("bangs", "black"), cloth=(20, 140, 150), boy=True, cls="crew", brow="black", glasses="sun"),
    dict(bg=((225, 170, 70), (190, 120, 30)), skin="brown", hair=("long", "black"), cloth=(190, 120, 30), girl=True, cls="vneck", brow="black", lashes=True, freckles=True),
]


def render(spec):
    a = Art()
    c1, c2 = spec["bg"]
    background(a, c1, c2)
    if spec.get("robot"):
        robot(a, None)
        return finish(a)

    skin = SK[spec["skin"]]
    hair_style, hair_name = spec["hair"]
    hcol = HC[hair_name]
    cloth = spec["cloth"]
    female = spec.get("girl", False)

    # arka: uzun sac / topuz kuyrugu / kedi kulaklari / basortusu
    outer = None
    if spec.get("hijab"):
        outer = hijab(a, spec["hijab"])
    if hair_style == "long":
        hair_long_back(a, hcol)
    elif hair_style == "bob":
        hair_bob_back(a, hcol)

    body(a, cloth, skin, spec.get("cls", "crew"))
    if spec.get("hijab"):
        # basortusu omuzlara sarkiyor: govdeden sonra bir kez daha ust katman
        col = spec["hijab"]
        pass
    hm = head(a, skin, ears=not spec.get("hijab") and hair_style not in ("long", "bob"))
    face(a, skin, None, HC.get(spec.get("brow", "black"), (40, 30, 30)), female=female,
         lashes=spec.get("lashes", False), eye_style=spec.get("eye_style", "oval"),
         freckles=spec.get("freckles", False))

    if spec.get("ears"):
        cat_ears(a, *spec["ears"])
    if hair_style == "bangs":
        hair_bangs(a, hcol)
    elif hair_style == "bun":
        hair_bun(a, hcol)
    elif hair_style == "long":
        hair_long(a, hcol)
    elif hair_style == "bob":
        hair_bob(a, hcol)
    elif hair_style == "curly":
        hair_curly(a, hcol)
    elif hair_style == "ponytail":
        hair_ponytail(a, hcol)

    if spec.get("beard"):
        beard(a, HC[spec["beard"]], "full", skin)
    if spec.get("mustache"):
        mustache(a, HC[spec["mustache"]])
    if spec.get("hijab"):
        # yuz acikligi: oval acikliktan yuz gorunsun -> basortusunun on kismi
        col = spec["hijab"]
        op = P(spline([(160, 84), (192, 92), (208, 122), (210, 158), (200, 192), (180, 212), (160, 218), (140, 212), (120, 192), (110, 158), (112, 122), (128, 92)]))
        full_m = a.mask(lambda d: d.polygon(P(spline([(160, 46), (208, 58), (238, 104), (244, 170), (246, 232), (218, 266), (160, 274), (102, 266), (74, 232), (76, 170), (82, 104), (112, 58)])), fill=255))
        hole = a.mask(lambda d: d.polygon(op, fill=255))
        ring = ImageChops.subtract(full_m, hole)
        a.grad_paint(ring, lighter(col, 0.2), darker(col, 0.12), 70)
        a.clipped(ring, lambda s: (s.stroke([(120, 100), (100, 190)], lighter(col, 0.5), 5, 0.30), s.ellipse(166, 250, 60, 22, darker(col, 0.5), 0.3, blur=8)))
        # yuz golgesi
        a.stroke([(128, 92), (110, 158), (120, 192), (140, 212), (160, 218), (180, 212), (200, 192), (210, 158), (192, 92)], darker(col, 0.45), 2.0, 0.6)
    if spec.get("cap"):
        cap(a, spec["cap"])
    if spec.get("beanie"):
        beanie(a, spec["beanie"])
    if spec.get("phones"):
        headphones(a, spec["phones"])
    g = spec.get("glasses")
    if g == "round":
        glasses(a, rim=(40, 40, 60), round_=True)
    elif g == "round_red":
        glasses(a, rim=(190, 50, 60), round_=True)
    elif g == "sun":
        glasses(a, rim=(24, 24, 30), round_=False, sun=True)
    return finish(a)


def finish(a):
    # hafif genel yumusatma icin supersample'dan indir
    img = a.img.convert("RGB").resize((S, S), Image.LANCZOS)
    return img


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    for i, spec in enumerate(AVATARS, start=1):
        img = render(spec)
        # Palet indirgeme YOK: kucuk ayrintilar (dil, dis) buyuk arka plan renkleri
        # yuzunden yanlis renge kayiyordu; 320 px RGB zaten ~50 KB.
        path = os.path.join(OUT_DIR, "avatar_%02d.png" % i)
        img.save(path, "PNG", optimize=True)
        total += os.path.getsize(path)
        print("%s %5.1f KB" % (os.path.basename(path), os.path.getsize(path) / 1024))
    print("%d avatar, %.2f MB" % (len(AVATARS), total / 1024 / 1024))


if __name__ == "__main__":
    main()
