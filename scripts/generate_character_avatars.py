#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Modern / gercekci bitmoji tarzi kiz-erkek profil avatarlari (256x256 PNG).

Kullanim:
    python scripts/generate_character_avatars.py

Cikti: assets/avatars_characters/avatar_char_01.png ... _49.png

NEDEN PNG: Secilen hazir avatar, kaydederken `avatars` bucket'ina yuklenip
sirasadan bir avatar_url gibi saklaniyor; avatari gosteren hicbir ekran
degismek zorunda kalmiyor.

CIZIM MOTORU - neden boyle:
  Duz elips yigmak yerine KATMANLI + MASKELI bir boru hatti var. Gercekcilik
  su dort seyden geliyor, hepsi de "yumusak maske + Gaussian blur" ile
  yapiliyor (numpy yok, sadece Pillow):
    1) Konturu: yuzun kenarina dogru koyulasan ten, elmacikta aydinlik.
    2) Temas golgeleri: cene altindan boyuna, sac cizgisinin altindan alna,
       alt dudagin altindan cene ucuna. Derinlik hissi buradan cikiyor.
    3) Goz anatomisi: sklera + iris halkasi + gozbebegi + parlama noktasi +
       ust kapak (kirpik cizgisi) + kapak kivrimi. Nokta goz kullanilmiyor.
    4) Sicak golge/isik: golgeler siyaha degil koyu sicak kahveye, isiklar
       beyaza degil kremaya karisiyor (WARM_DARK / WARM_LIGHT).

  Silüetler (kafa, sac, dudak) Catmull-Rom spline'dan uretiliyor; elipsle
  cizilen bir cene "organik" durmuyor, spline duruyor.

KATALOG (append-only): SKINS / HAIRS / BGS / CHARACTERS listelerine yalnizca
SONA ekleme yapilir. Liste sirasi dosya adini (avatar_char_NN.png) belirliyor
ve kullanicilarin secmis oldugu avatar_url o dosya adina bagli; araya ekleme
ya da siralama degisikligi baskasinin avatarini degistirir.
"""

import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 256          # yayinlanan kare boyu (px)
SS = 4              # supersampling carpani
C = SIZE * SS       # supersample edilmis tuval boyu

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets",
    "avatars_characters",
)

# --- Palet (APPEND-ONLY: var olan indeksler/anahtarlar degistirilmez) --------
SKINS = [
    (0xF6, 0xD1, 0xB0),
    (0xEC, 0xBB, 0x92),
    (0xD9, 0xA0, 0x72),
    (0xB2, 0x7B, 0x4F),
    (0x8B, 0x57, 0x36),
    (0x5C, 0x38, 0x22),
]

HAIRS = {
    "siyah": (0x20, 0x1C, 0x1B),
    "koyu_kahve": (0x3C, 0x2A, 0x20),
    "kahve": (0x6B, 0x45, 0x2B),
    "kizil": (0x8E, 0x3C, 0x25),
    "sari": (0xD8, 0xAA, 0x55),
    "gri": (0xA0, 0x9C, 0x99),
    "bakir": (0xB5, 0x5A, 0x2E),
    "beyaz": (0xE8, 0xE6, 0xE1),
}

BGS = [
    (0x5B, 0x8F, 0xE8),
    (0xF4, 0xC4, 0x4E),
    (0xE0, 0x8B, 0x4C),
    (0x62, 0xC2, 0x8F),
    (0xE8, 0x8F, 0xA8),
    (0x9B, 0x8F, 0xE8),
    (0x54, 0xC0, 0xD3),
    (0xC7, 0xA5, 0x7B),
    (0xD9, 0x5B, 0x5B),
    (0x8F, 0xA8, 0x6B),
]

WHITE = (0xFF, 0xFF, 0xFF)
SCLERA = (0xFA, 0xF6, 0xF4)
GOLD = (0xE3, 0xBE, 0x55)
FRAME = (0x2E, 0x31, 0x38)
# Golge siyaha degil sicak kahveye, isik beyaza degil kremaya karisir.
WARM_DARK = (0x35, 0x18, 0x14)
WARM_LIGHT = (0xFF, 0xF4, 0xE4)
ROSE = (0xBE, 0x5F, 0x58)

# --- Yuz olculeri (tasarim koordinati, 0-256) -------------------------------
CX = 128.0
HEAD_TOP = 36.0
CHIN_Y = 165.0
HEAD_MID = 102.0       # kafanin dikey merkezi (olcekleme burdan yapilir)
EYE_Y = 101.0
EYE_DX = 29.0
BROW_Y = 85.0
NOSE_Y = 126.0         # burun ucu / kanat hizasi
MOUTH_Y = 145.0
EAR_TOP, EAR_BOT = 93.0, 123.0
NECK_TOP, NECK_BOT, NECK_HW = 148.0, 202.0, 21.0
BODY_TOP = 192.0


# ---------------------------------------------------------------- renk ----
def mix(a, b, f):
    f = max(0.0, min(1.0, f))
    return tuple(int(round(a[i] + (b[i] - a[i]) * f)) for i in range(3))


def darken(c, f=0.25):
    return mix(c, (0, 0, 0), f)


def lighten(c, f=0.25):
    return mix(c, WHITE, f)


def shade(c, f):
    """Sicak golge - tende/sacta siyaha dusmeden koyulasir."""
    return mix(c, WARM_DARK, f)


def glow(c, f):
    """Sicak isik - beyaza patlamadan aydinlanir."""
    return mix(c, WARM_LIGHT, f)


# ------------------------------------------------------------ geometri ----
def s(v):
    """Tasarim koordinatini (0-256) supersample tuvaline cevirir."""
    return v * SS


def P(pts):
    return [(x * SS, y * SS) for x, y in pts]


def box(x0, y0, x1, y1):
    """Kutu - kenarlar her zaman sirali (ayna cizimlerde x1 < x0 olabiliyor)."""
    return [s(min(x0, x1)), s(min(y0, y1)), s(max(x0, x1)), s(max(y0, y1))]


def circ(cx, cy, r):
    return [s(cx - r), s(cy - r), s(cx + r), s(cy + r)]


def spline(points, closed=True, steps=14):
    """Catmull-Rom: kontrol noktalarindan gecen yumusak egri.

    Cene/dudak/sac silueti elipsle 'geometrik' duruyor; spline organik.
    """
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
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t
                       + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t
                       + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    if not closed:
        out.append(points[-1])
    return out


def scale_pts(pts, k, cx=CX, cy=HEAD_MID):
    return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in pts]


def head_points(v):
    """Kafa silueti: yumurta formu - elmacikta genis, cenede daralan."""
    jaw, chin, cheek = v["jaw"], v["chin"], v["cheek"]
    right = [
        (CX, HEAD_TOP),
        (CX + 33, HEAD_TOP + 3),
        (CX + 52 * cheek, 53),
        (CX + 58 * cheek, 78),
        (CX + 57 * cheek, 101),
        (CX + 52 * jaw, 124),
        (CX + 42 * jaw, 144),
        (CX + 26 * chin, 158),
        (CX, CHIN_Y + (chin - 1.0) * 7),
    ]
    left = [(2 * CX - x, y) for x, y in reversed(right[1:-1])]
    return right + left


def width_fn(head):
    """y -> kafanin o yukseklikteki yari genisligi (sac kenarlarini oturtmak icin)."""
    rows = {}
    for x, y in head:
        k = int(round(y))
        rows[k] = max(rows.get(k, 0.0), abs(x - CX))
    keys = sorted(rows)

    def hw(y):
        y = max(keys[0], min(keys[-1], y))
        lo = keys[0]
        for k in keys:
            if k <= y:
                lo = k
            else:
                f = (y - lo) / max(k - lo, 1e-6)
                return rows[lo] + (rows[k] - rows[lo]) * f
        return rows[lo]

    return hw


# -------------------------------------------------------- katman/maske ----
def mask_of(fn):
    """fn(draw) ile 255 dolgu cizer, L maskesi dondurur."""
    m = Image.new("L", (C, C), 0)
    fn(ImageDraw.Draw(m))
    return m


def poly(points, closed=True, steps=14):
    pts = P(spline(points, closed=closed, steps=steps))
    return lambda d: d.polygon(pts, fill=255)


def soften(mask, radius):
    return mask.filter(ImageFilter.GaussianBlur(s(radius))) if radius else mask


def clip(mask, to):
    return ImageChops.multiply(mask, to)


def paint(img, mask, color, alpha=1.0):
    """Maskeyi renkle boyayip tuvale bindirir."""
    if alpha < 1.0:
        mask = mask.point(lambda v: int(v * alpha))
    layer = Image.new("RGBA", (C, C), color + (0,))
    layer.putalpha(mask)
    img.alpha_composite(layer)


def shadow(img, shape_fn, color, alpha, radius, into=None):
    """Yumusak golge/isik: ciz -> blurla -> (gerekirse) kirp -> bindir."""
    m = soften(mask_of(shape_fn), radius)
    if into is not None:
        m = clip(m, into)
    paint(img, m, color, alpha)


# ------------------------------------------------------------- arkaplan ----
def background(bg):
    """Duz zemin yerine yumusak radyal gradyan - modern sticker hissi."""
    base = Image.new("RGB", (C, C), darken(bg, 0.17))
    g = Image.radial_gradient("L").resize((C * 2, C * 2), Image.BILINEAR)
    left, top = int(C * 0.5), int(C * 0.66)      # isik merkezi yukari kaydirilir
    g = g.crop((left, top, left + C, top + C)).point(lambda x: 255 - x)
    hi = Image.new("RGB", (C, C), lighten(bg, 0.20))
    return Image.composite(hi, base, g).convert("RGBA")


# ---------------------------------------------------------------- govde ----
def draw_body(img, cloth, collar_style="crew"):
    shoulders = [
        (CX - 108, 262), (CX - 100, 224), (CX - 66, 200),
        (CX - 30, 191), (CX, 189), (CX + 30, 191),
        (CX + 66, 200), (CX + 100, 224), (CX + 108, 262),
        (CX + 108, 300), (CX - 108, 300),
    ]
    paint(img, mask_of(poly(shoulders)), cloth)
    body = mask_of(poly(shoulders))

    # omuz yuvarlakligi: kenarlar koyu, gogus ortasi acik
    shadow(img, lambda d: d.ellipse(circ(CX - 96, 250, 46), fill=255),
           shade(cloth, 0.55), 0.45, 9, into=body)
    shadow(img, lambda d: d.ellipse(circ(CX + 96, 250, 46), fill=255),
           shade(cloth, 0.55), 0.45, 9, into=body)
    shadow(img, lambda d: d.ellipse(box(CX - 46, 206, CX + 46, 268), fill=255),
           glow(cloth, 0.28), 0.35, 12, into=body)

    # yaka
    if collar_style == "crew":
        neck_hole = [
            (CX - 30, 196), (CX - 20, 210), (CX, 215),
            (CX + 20, 210), (CX + 30, 196),
            (CX + 26, 191), (CX, 188), (CX - 26, 191),
        ]
        paint(img, mask_of(poly(neck_hole)), lighten(cloth, 0.14))
        shadow(img, poly(scale_pts(neck_hole, 0.86, CX, 202)),
               shade(cloth, 0.6), 0.5, 3, into=body)


def draw_neck(img, skin, face):
    neck = [
        (CX - NECK_HW, NECK_TOP), (CX - NECK_HW - 1, 178),
        (CX - NECK_HW - 4, NECK_BOT), (CX + NECK_HW + 4, NECK_BOT),
        (CX + NECK_HW + 1, 178), (CX + NECK_HW, NECK_TOP),
    ]
    m = mask_of(poly(neck))
    paint(img, m, shade(skin, 0.10))
    # ceneden boyuna dusen golge: derinligin ana kaynagi
    shadow(img, lambda d: d.ellipse(box(CX - 40, 132, CX + 40, 180), fill=255),
           shade(skin, 0.55), 0.85, 7, into=m)
    shadow(img, lambda d: d.ellipse(box(CX - 34, 126, CX + 34, 168), fill=255),
           shade(skin, 0.7), 0.5, 5, into=m)
    # boynun yan kenarlarinda hafif koyulasma
    shadow(img, lambda d: d.rectangle(box(CX - NECK_HW - 6, NECK_TOP, CX - NECK_HW + 4, NECK_BOT), fill=255),
           shade(skin, 0.45), 0.5, 4, into=m)
    shadow(img, lambda d: d.rectangle(box(CX + NECK_HW - 4, NECK_TOP, CX + NECK_HW + 6, NECK_BOT), fill=255),
           shade(skin, 0.45), 0.5, 4, into=m)


# ----------------------------------------------------------------- kafa ----
def draw_ears(img, skin, hw, v):
    for side in (-1, 1):
        ex = CX + side * (hw(108) - 3)
        ear = [
            (ex, EAR_TOP), (ex + side * 7, EAR_TOP + 5),
            (ex + side * 8, 109), (ex + side * 4, EAR_BOT - 3),
            (ex - side * 3, EAR_BOT - 5),
        ]
        m = mask_of(poly(ear))
        paint(img, m, skin)
        shadow(img, lambda d, e=ex, sd=side: d.ellipse(
            box(e - 4, EAR_TOP + 4, e + sd * 8, EAR_BOT - 4), fill=255),
            shade(skin, 0.45), 0.55, 2.5, into=m)
        shadow(img, lambda d, e=ex, sd=side: d.ellipse(
            box(e + sd * 2, 104, e + sd * 9, EAR_BOT - 2), fill=255),
            shade(skin, 0.3), 0.5, 3, into=m)


def draw_face(img, skin, head, face, v):
    paint(img, face, skin)

    # 1) kontur: kenara dogru koyulasan ten (ic siluet cikarilir -> halka)
    rim = ImageChops.subtract(face, mask_of(poly(scale_pts(head, 0.87, CX, HEAD_MID - 4))))
    paint(img, clip(soften(rim, 7), face), shade(skin, 0.5), 0.34)

    # 2) cene alti ve sakaklar biraz daha koyu
    shadow(img, lambda d: d.ellipse(box(CX - 44, 138, CX + 44, 182), fill=255),
           shade(skin, 0.55), 0.30, 9, into=face)
    for side in (-1, 1):
        shadow(img, lambda d, sd=side: d.ellipse(
            box(CX + sd * 34, 62, CX + sd * 62, 118), fill=255),
            shade(skin, 0.45), 0.22, 10, into=face)

    # 3) alin ve elmacik isiklari
    shadow(img, lambda d: d.ellipse(box(CX - 30, 56, CX + 30, 92), fill=255),
           glow(skin, 0.55), 0.30, 10, into=face)
    for side in (-1, 1):
        shadow(img, lambda d, sd=side: d.ellipse(
            box(CX + sd * 16, 104, CX + sd * 44, 128), fill=255),
            glow(skin, 0.45), 0.22, 8, into=face)
    # burun sirti isigi
    shadow(img, lambda d: d.ellipse(box(CX - 6, 96, CX + 6, 124), fill=255),
           glow(skin, 0.5), 0.28, 5, into=face)


def draw_brows(img, v, hair, face):
    col = shade(hair, 0.25) if sum(hair) > 250 else mix(hair, (0x2A, 0x20, 0x1C), 0.35)
    th = v["brow"]
    arch = v["brow_arch"]
    for side in (-1, 1):
        bx = CX + side * EYE_DX
        inner = bx + side * 15.5
        outer = bx - side * 15.5
        top = [
            (outer, BROW_Y + 3.6),
            (bx - side * 6, BROW_Y - 1.4 * arch),
            (bx + side * 5, BROW_Y - 2.4 * arch),
            (inner, BROW_Y + 1.6),
        ]
        bottom = [
            (inner, BROW_Y + 1.6 + 3.4 * th),
            (bx + side * 5, BROW_Y - 2.4 * arch + 4.2 * th),
            (bx - side * 6, BROW_Y - 1.4 * arch + 4.0 * th),
            (outer, BROW_Y + 3.6 + 1.0 * th),
        ]
        pts = P(spline(top, closed=False, steps=10) + spline(bottom, closed=False, steps=10))
        m = mask_of(lambda d, p=pts: d.polygon(p, fill=255))
        m = clip(soften(m, 0.5), face)
        paint(img, m, col, 0.95)
        # kasin alt kenarinda cok hafif yumusama (kil hissi)
        paint(img, clip(soften(m, 1.6), face), col, 0.3)


def eye_points(ex, ey, hw, hh, inner):
    o = -inner
    return [
        (ex + o * hw, ey + 1.0),
        (ex + o * hw * 0.58, ey - hh * 0.86),
        (ex - o * hw * 0.12, ey - hh * 1.0),
        (ex + inner * hw * 0.70, ey - hh * 0.56),
        (ex + inner * hw, ey + 2.0),
        (ex + inner * hw * 0.60, ey + hh * 0.78),
        (ex - inner * hw * 0.10, ey + hh * 0.94),
        (ex + o * hw * 0.66, ey + hh * 0.62),
    ]


def draw_eyes(img, v, skin, eye_color, lash_on, face):
    hw = 13.6 * v["eye_w"]
    hh = 8.4 * v["eye_h"]
    lash_col = (0x24, 0x1C, 0x1E)
    for side in (-1, 1):
        ex = CX + side * EYE_DX
        inner = -side                      # buruna bakan yon
        pts = eye_points(ex, EYE_Y, hw, hh, inner)
        eye = mask_of(poly(pts))

        paint(img, eye, SCLERA)
        # ust kapaktan sklera uzerine dusen golge
        shadow(img, lambda d, e=ex: d.ellipse(
            box(e - hw, EYE_Y - hh - 4, e + hw, EYE_Y - hh * 0.05), fill=255),
            (0x9A, 0x82, 0x84), 0.55, 2, into=eye)

        # iris: dis halka koyu, alt ic kisim acik -> derinlik
        ix, iy, ir = ex + inner * 0.8, EYE_Y - 0.8, 8.3
        iris = clip(mask_of(lambda d: d.ellipse(circ(ix, iy, ir), fill=255)), eye)
        paint(img, iris, darken(eye_color, 0.35))
        paint(img, clip(mask_of(lambda d: d.ellipse(circ(ix, iy, ir * 0.82), fill=255)), eye),
              eye_color)
        shadow(img, lambda d: d.ellipse(circ(ix, iy + ir * 0.34, ir * 0.62), fill=255),
               lighten(eye_color, 0.42), 0.75, 2, into=iris)
        shadow(img, lambda d: d.ellipse(circ(ix, iy - ir * 0.5, ir * 0.7), fill=255),
               darken(eye_color, 0.5), 0.5, 2.5, into=iris)
        paint(img, clip(mask_of(lambda d: d.ellipse(circ(ix, iy, 3.5), fill=255)), eye),
              (0x14, 0x10, 0x12))
        # parlama: buyuk ust-sol + kucuk alt-sag
        paint(img, clip(mask_of(lambda d: d.ellipse(circ(ix - 2.8, iy - 3.0, 2.5), fill=255)), eye),
              WHITE, 0.95)
        paint(img, clip(mask_of(lambda d: d.ellipse(circ(ix + 3.2, iy + 2.8, 1.2), fill=255)), eye),
              WHITE, 0.6)

        # ust kapak / kirpik cizgisi (disa dogru kalinlasir)
        top_curve = spline(pts[:5], closed=False, steps=12)
        img_line = Image.new("L", (C, C), 0)
        ImageDraw.Draw(img_line).line(P(top_curve), fill=255,
                                      width=int(s(2.0 + (1.0 if lash_on else 0.0))),
                                      joint="curve")
        paint(img, img_line, lash_col)
        if lash_on:
            tip = pts[0]
            paint(img, mask_of(poly([
                (tip[0], tip[1] - 1.2),
                (tip[0] - side * 5.5, tip[1] - 5.0),
                (tip[0] - side * 1.0, tip[1] + 1.4),
            ], steps=8)), lash_col)

        # alt kapak: ince, yumusak
        low = Image.new("L", (C, C), 0)
        ImageDraw.Draw(low).line(P(spline(pts[4:] + [pts[0]], closed=False, steps=12)),
                                 fill=255, width=int(s(1.0)), joint="curve")
        paint(img, clip(soften(low, 0.6), face), shade(skin, 0.45), 0.5)

        # kapak kivrimi (goz kapaginin ustundeki cizgi)
        crease = Image.new("L", (C, C), 0)
        ImageDraw.Draw(crease).line(P(spline([
            (ex - hw * 0.85, EYE_Y - hh * 0.75),
            (ex, EYE_Y - hh * 1.55),
            (ex + hw * 0.85, EYE_Y - hh * 0.72),
        ], closed=False, steps=10)), fill=255, width=int(s(1.2)), joint="curve")
        paint(img, clip(soften(crease, 1.1), face), shade(skin, 0.5), 0.35)


def draw_nose(img, v, skin, face):
    w = 9.5 * v["nose"]
    # kanat/uc golgesi - sert kenar yok, hep blurlu
    shadow(img, lambda d: d.ellipse(box(CX - w, NOSE_Y - 11, CX + w, NOSE_Y + 3), fill=255),
           shade(skin, 0.45), 0.42, 4.5, into=face)
    # sol sirt golgesi (isik sagdan geliyor kabulu)
    shadow(img, lambda d: d.ellipse(box(CX - w * 0.95, 104, CX - w * 0.2, NOSE_Y - 1), fill=255),
           shade(skin, 0.4), 0.30, 5, into=face)
    # burun ucu isigi
    shadow(img, lambda d: d.ellipse(box(CX - 4.5, NOSE_Y - 9, CX + 5.5, NOSE_Y - 1), fill=255),
           glow(skin, 0.6), 0.45, 3, into=face)
    # burun delikleri: yumusak, koyu ama siyah degil
    for side in (-1, 1):
        shadow(img, lambda d, sd=side: d.ellipse(
            box(CX + sd * w * 0.34, NOSE_Y - 2.6, CX + sd * w * 0.86, NOSE_Y + 0.8), fill=255),
            shade(skin, 0.75), 0.6, 1.1, into=face)
    # kanat kivrimlari
    for side in (-1, 1):
        shadow(img, lambda d, sd=side: d.arc(
            box(CX + sd * w * 0.2, NOSE_Y - 8, CX + sd * w * 1.25, NOSE_Y + 2.5),
            0 if sd > 0 else 140, 40 if sd > 0 else 180,
            fill=255, width=int(s(1.1))),
            shade(skin, 0.5), 0.35, 1.2, into=face)


def draw_mouth(img, v, skin, face):
    w = 15.0 * v["lips"]
    lift = 3.2 * v["smile"]
    lipf = v["lips"]
    rose = mix(skin, ROSE, 0.62)
    upper = shade(rose, 0.22)
    lower = glow(rose, 0.10)

    corner_l = (CX - w, MOUTH_Y - lift)
    corner_r = (CX + w, MOUTH_Y - lift)
    line_pts = [corner_l, (CX - w * 0.5, MOUTH_Y + 0.8),
                (CX, MOUTH_Y + 1.3), (CX + w * 0.5, MOUTH_Y + 0.8), corner_r]

    if v["teeth"]:
        # acik gulus: dis bandi + ust dudak golgesi
        gap = [corner_l, (CX - w * 0.5, MOUTH_Y + 1.0), (CX, MOUTH_Y + 1.8),
               (CX + w * 0.5, MOUTH_Y + 1.0), corner_r,
               (CX + w * 0.42, MOUTH_Y + 5.4), (CX, MOUTH_Y + 6.6),
               (CX - w * 0.42, MOUTH_Y + 5.4)]
        gm = mask_of(poly(gap))
        paint(img, gm, (0xF7, 0xF1, 0xEE))
        shadow(img, lambda d: d.ellipse(
            box(CX - w, MOUTH_Y - 3, CX + w, MOUTH_Y + 2.6), fill=255),
            (0x7A, 0x46, 0x44), 0.6, 1.6, into=gm)
        mouth_low_top = [corner_l, (CX - w * 0.42, MOUTH_Y + 5.4),
                         (CX, MOUTH_Y + 6.6), (CX + w * 0.42, MOUTH_Y + 5.4), corner_r]
    else:
        mouth_low_top = line_pts

    up_poly = [corner_l,
               (CX - w * 0.44, MOUTH_Y - 3.4 * lipf),
               (CX - w * 0.14, MOUTH_Y - 2.0 * lipf),
               (CX, MOUTH_Y - 2.9 * lipf),
               (CX + w * 0.14, MOUTH_Y - 2.0 * lipf),
               (CX + w * 0.44, MOUTH_Y - 3.4 * lipf),
               corner_r] + list(reversed(line_pts[1:-1]))
    paint(img, clip(mask_of(poly(up_poly)), face), upper)

    low_poly = mouth_low_top + [
        (CX + w * 0.62, MOUTH_Y + 4.6 * lipf + (2.0 if v["teeth"] else 0)),
        (CX, MOUTH_Y + 6.4 * lipf + (2.0 if v["teeth"] else 0)),
        (CX - w * 0.62, MOUTH_Y + 4.6 * lipf + (2.0 if v["teeth"] else 0)),
    ]
    lm = clip(mask_of(poly(low_poly)), face)
    paint(img, lm, lower)
    shadow(img, lambda d: d.ellipse(
        box(CX - w * 0.42, MOUTH_Y + 2.4, CX + w * 0.42, MOUTH_Y + 6.0), fill=255),
        glow(rose, 0.55), 0.5, 2, into=lm)

    # dudak arasi cizgi + alt dudak alti golgesi (cene kivrimi)
    line = Image.new("L", (C, C), 0)
    ImageDraw.Draw(line).line(P(spline(line_pts, closed=False, steps=12)),
                              fill=255, width=int(s(1.0)), joint="curve")
    paint(img, clip(soften(line, 0.5), face), shade(rose, 0.55), 0.7)
    shadow(img, lambda d: d.ellipse(
        box(CX - w * 0.7, MOUTH_Y + 6.5 * lipf, CX + w * 0.7, MOUTH_Y + 12.0), fill=255),
        shade(skin, 0.4), 0.28, 3.5, into=face)
    # agiz koselerinde kucuk golge (gulus vurgusu)
    for side in (-1, 1):
        shadow(img, lambda d, sd=side: d.ellipse(
            circ(CX + sd * w, MOUTH_Y - lift, 2.2), fill=255),
            shade(skin, 0.55), 0.45, 1.6, into=face)


def draw_blush(img, skin, face, strength=0.5):
    for side in (-1, 1):
        shadow(img, lambda d, sd=side: d.ellipse(
            box(CX + sd * 20, 118, CX + sd * 46, 136), fill=255),
            mix(skin, (0xE0, 0x6A, 0x62), 0.75), 0.22 * strength / 0.5, 8, into=face)


# ------------------------------------------------------------------ sac ----
HAIR_SPECS = {
    "kel": dict(kind="bald"),
    "kisa": dict(vol=0.20, hl=64, fringe="round", side=0.26),
    "dikenli": dict(vol=0.30, hl=62, fringe="round", side=0.22, spikes=True),
    "yandan_ayrik": dict(vol=0.30, hl=63, fringe="side", side=0.28),
    "kivircik": dict(vol=0.52, hl=64, fringe="round", side=0.34, texture="curly"),
    "dagınık": dict(vol=0.40, hl=62, fringe="messy", side=0.26, texture="tousled"),
    "uzun": dict(vol=0.28, hl=63, fringe="round", side=1.0, back="long"),
    "uzun_dalgali": dict(vol=0.36, hl=63, fringe="curtain", side=1.0, back="long",
                         texture="wavy"),
    "bob": dict(vol=0.30, hl=67, fringe="blunt", side=0.92, back="bob"),
    "atkuyrugu": dict(vol=0.24, hl=64, fringe="round", side=0.34, back="pony"),
    "topuz": dict(vol=0.20, hl=64, fringe="round", side=0.30, back="bun"),
    "yarim_topuz": dict(vol=0.30, hl=63, fringe="curtain", side=0.92, back="halfbun"),
    "iki_orgu": dict(vol=0.26, hl=66, fringe="blunt", side=0.40, back="pigtails"),
    "tek_orgu": dict(vol=0.24, hl=64, fringe="round", side=0.34, back="braid"),
    "basortu": dict(kind="scarf"),
    "sapka": dict(kind="cap", vol=0.22, hl=64, side=0.24),
    "bere": dict(kind="beanie", vol=0.30, side=0.26),
}


def hairline(fringe, hl):
    """Sac cizgisi - SAGDAN SOLA (kep poligonunu kapatmak icin)."""
    if fringe == "blunt":          # kakul: alni kapatan duz kesim
        return [(CX + 44, hl + 15), (CX + 20, hl + 21), (CX, hl + 22),
                (CX - 20, hl + 21), (CX - 44, hl + 15)]
    if fringe == "side":
        # Yandan ayrik: ayrim saginda yuksek, sol alni SUPURUP kapatir.
        # Sol ucu sac cizgisinin ustune cikarirsak sac dokuluyormus gibi duruyor.
        return [(CX + 48, hl + 5), (CX + 26, hl + 3), (CX + 2, hl + 14),
                (CX - 24, hl + 19), (CX - 48, hl + 12)]
    if fringe == "curtain":        # ortadan ayrik perde kakul
        return [(CX + 46, hl + 13), (CX + 19, hl + 16), (CX, hl + 1),
                (CX - 19, hl + 16), (CX - 46, hl + 13)]
    if fringe == "messy":          # dagınık: duzensiz
        return [(CX + 45, hl + 9), (CX + 22, hl + 2), (CX + 4, hl + 13),
                (CX - 16, hl + 1), (CX - 34, hl + 11), (CX - 46, hl + 3)]
    return [(CX + 43, hl + 7), (CX + 21, hl - 3), (CX, hl - 1),
            (CX - 21, hl - 3), (CX - 43, hl + 7)]


def cap_polygon(hw, spec):
    vol = spec.get("vol", 0.3)
    side_y = 104 + spec.get("side", 0.5) * 58
    pad = 3.0 + 2.5 * vol
    ys = [side_y, side_y - 16, 118, 104, 92]
    pts = [(CX - (hw(y) + pad), y) for y in ys]
    pts += [
        (CX - (hw(74) + pad + 1), 74),
        (CX - 46, 52 - 9 * vol),
        (CX - 25, 40 - 15 * vol),
        (CX, 35 - 19 * vol),
        (CX + 25, 40 - 15 * vol),
        (CX + 46, 52 - 9 * vol),
        (CX + (hw(74) + pad + 1), 74),
    ]
    pts += [(CX + (hw(y) + pad), y) for y in reversed(ys)]
    pts += hairline(spec.get("fringe", "round"), spec.get("hl", 64))
    return pts


def texture_mask(base, kind, hw, spec):
    """Kivircik/dagınık dokular: siluete tutam/bukle ekler."""
    if kind == "curly":
        # Bukleler yalnizca UST siluete eklenir. Tam daire donulurse alttaki
        # tutamlar yanaklarin uzerine koca lekeler halinde biniyor.
        extra = Image.new("L", (C, C), 0)
        d = ImageDraw.Draw(extra)
        vol = spec.get("vol", 0.4)
        rx, ry = 54 + 8 * vol, 46 + 10 * vol
        cy = HEAD_MID - 30
        for deg in range(-186, 7, 13):
            a = math.radians(deg)
            d.ellipse(circ(CX + rx * math.cos(a), cy + ry * math.sin(a),
                           10 + 3 * vol), fill=255)
        return ImageChops.lighter(base, extra)
    if kind == "tousled":
        extra = Image.new("L", (C, C), 0)
        d = ImageDraw.Draw(extra)
        for x, y, r in ((CX - 44, 58, 15), (CX - 20, 42, 17), (CX + 8, 38, 16),
                        (CX + 34, 45, 16), (CX + 52, 66, 14), (CX - 56, 74, 13)):
            d.ellipse(circ(x, y, r), fill=255)
        return ImageChops.lighter(base, extra)
    return base


def spike_mask(base):
    """Dikenler yalnizca tepe ortasinda; kenara tasarsa 'boynuz' gibi duruyor."""
    extra = Image.new("L", (C, C), 0)
    d = ImageDraw.Draw(extra)
    # Kep kubbesi ortada yuksek, kenarda alcak. Sabit yukseklikte diken
    # koyarsak ortadakiler kubbenin icinde kaybolup yalnizca kenardakiler
    # disari tasiyor - tepe "boynuz" gibi cikiyor. Tipler kubbeyi takip eder.
    for i in range(5):
        x = CX - 28 + i * 14
        lean = -5 if i % 2 else 4
        tip = 20 + abs(i - 2) * 3 + (2 if i % 2 else 0)
        d.polygon(P([(x - 11, 54), (x + lean, tip), (x + 11, 54)]), fill=255)
    return ImageChops.lighter(base, extra)


def back_hair_mask(kind, hw, spec):
    if kind == "long":
        pts = [(CX - 60, 62), (CX - 68, 110), (CX - 64, 168), (CX - 56, 208),
               (CX, 216), (CX + 56, 208), (CX + 64, 168), (CX + 68, 110),
               (CX + 60, 62), (CX, 44)]
        m = mask_of(poly(pts))
        if spec.get("texture") == "wavy":
            extra = Image.new("L", (C, C), 0)
            d = ImageDraw.Draw(extra)
            for x in (CX - 62, CX - 34, CX + 34, CX + 62):
                for y in (176, 198):
                    d.ellipse(circ(x, y, 17), fill=255)
            m = ImageChops.lighter(m, extra)
        return m
    if kind == "bob":
        pts = [(CX - 58, 66), (CX - 64, 112), (CX - 58, 150), (CX - 40, 162),
               (CX, 166), (CX + 40, 162), (CX + 58, 150), (CX + 64, 112),
               (CX + 58, 66), (CX, 46)]
        return mask_of(poly(pts))
    if kind == "pony":
        m = mask_of(poly([(CX + 44, 78), (CX + 74, 92), (CX + 82, 126),
                          (CX + 74, 158), (CX + 58, 166), (CX + 46, 140),
                          (CX + 42, 108)]))
        return m
    if kind == "bun":
        return mask_of(lambda d: d.ellipse(circ(CX, 40, 25), fill=255))
    if kind == "halfbun":
        m = back_hair_mask("long", hw, dict(texture=spec.get("texture")))
        return ImageChops.lighter(
            m, mask_of(lambda d: d.ellipse(circ(CX, 40, 20), fill=255)))
    if kind == "pigtails":
        m = Image.new("L", (C, C), 0)
        d = ImageDraw.Draw(m)
        for side in (-1, 1):
            for i, y in enumerate(range(116, 188, 17)):
                r = 13 - i * 1.2
                d.ellipse(circ(CX + side * (62 + i * 2), y, r), fill=255)
        return m
    if kind == "braid":
        m = Image.new("L", (C, C), 0)
        d = ImageDraw.Draw(m)
        for i, y in enumerate(range(112, 200, 16)):
            r = 14 - i * 1.1
            d.ellipse(circ(CX + 46 + i * 1.5, y, r), fill=255)
        return m
    return None


def hair_dark(hair):
    return shade(hair, 0.45) if sum(hair) > 200 else mix(hair, (0x05, 0x04, 0x06), 0.45)


def draw_back_hair(img, spec, hair, hw):
    """Arka sac kutlesi - govdeden ONCE cizilir ki omuzlarin arkasinda kalsin."""
    back = spec.get("back")
    if not back:
        return
    bm = back_hair_mask(back, hw, spec)
    if bm is None:
        return
    dark = hair_dark(hair)
    paint(img, bm, mix(hair, dark, 0.40))
    shadow(img, lambda d: d.ellipse(box(CX - 74, 150, CX + 74, 236), fill=255),
           dark, 0.5, 12, into=bm)
    shadow(img, lambda d: d.ellipse(box(CX - 40, 30, CX + 40, 90), fill=255),
           glow(hair, 0.25), 0.30, 10, into=bm)


def draw_hair(img, spec, hair, skin, face, hw):
    """Sac kepi: kutle -> derinlik -> parlama -> alna dusen golge."""
    dark = hair_dark(hair)
    # Koyu sacta yuksek karisim tan/turuncu bir bant gibi duruyor; parlaklik
    # sacin kendi tonuna yakin kalmali.
    hi = glow(hair, 0.22) if sum(hair) < 620 else lighten(hair, 0.22)

    cap = mask_of(poly(cap_polygon(hw, spec)))
    if spec.get("spikes"):
        cap = spike_mask(cap)
    cap = texture_mask(cap, spec.get("texture"), hw, spec)
    paint(img, cap, hair)

    # koklerde/kenarlarda koyulasma
    shadow(img, lambda d: d.ellipse(box(CX - 70, 96, CX + 70, 190), fill=255),
           dark, 0.5, 10, into=cap)
    for side in (-1, 1):
        shadow(img, lambda d, sd=side: d.ellipse(
            box(CX + sd * 40, 40, CX + sd * 78, 150), fill=255), dark, 0.35, 12, into=cap)

    # parlama: sac cizgisini takip eden yumusak bant (modern hissin anahtari)
    gloss = Image.new("L", (C, C), 0)
    ImageDraw.Draw(gloss).line(P(spline([
        (CX - 44, 62), (CX - 20, 48), (CX + 12, 45), (CX + 40, 57)],
        closed=False, steps=12)), fill=255, width=int(s(9)), joint="curve")
    paint(img, clip(soften(gloss, 5), cap), hi, 0.38)
    gloss2 = Image.new("L", (C, C), 0)
    ImageDraw.Draw(gloss2).line(P(spline([
        (CX - 38, 66), (CX - 14, 54), (CX + 16, 52)],
        closed=False, steps=10)), fill=255, width=int(s(3.5)), joint="curve")
    paint(img, clip(soften(gloss2, 2), cap), glow(hi, 0.30), 0.30)

    # ayrim cizgisi (yandan ayrik stilde sacin nereden ayrildigini gosterir)
    if spec.get("fringe") == "side":
        part = Image.new("L", (C, C), 0)
        ImageDraw.Draw(part).line(P(spline([
            (CX + 24, spec.get("hl", 63) + 4), (CX + 28, 52), (CX + 22, 38)],
            closed=False, steps=10)), fill=255, width=int(s(2.2)), joint="curve")
        paint(img, clip(soften(part, 1.6), cap), dark, 0.55)

    # sacin alna dusurdugu golge
    hl_shadow = soften(cap, 4.5)
    hl_shadow = clip(hl_shadow, face)
    paint(img, hl_shadow, shade(skin, 0.6), 0.30)
    return cap


def draw_bald(img, skin, face):
    shadow(img, lambda d: d.ellipse(box(CX - 26, 48, CX + 20, 74), fill=255),
           glow(skin, 0.6), 0.35, 9, into=face)
    # hafif sac dibi golgesi (tamamen tirassiz durmasin)
    shadow(img, lambda d: d.ellipse(box(CX - 56, 60, CX + 56, 132), fill=255),
           shade(skin, 0.4), 0.16, 8, into=face)


def draw_scarf(img, hair, skin, face, hw):
    """Basortusu: sacin yerine gecer, omuza dogru dokulur."""
    col = hair
    drape = [(CX - 58, 70), (CX - 70, 120), (CX - 74, 172), (CX - 66, 206),
             (CX, 214), (CX + 66, 206), (CX + 74, 172), (CX + 70, 120),
             (CX + 58, 70), (CX + 30, 40), (CX, 33), (CX - 30, 40)]
    m = mask_of(poly(drape))
    # yuz aciklıgı: ten gorunen oval
    face_hole = mask_of(poly(
        [(CX, 52), (CX + 44, 66), (CX + 50, 104), (CX + 40, 140),
         (CX, 160), (CX - 40, 140), (CX - 50, 104), (CX - 44, 66)]))
    m = ImageChops.subtract(m, face_hole)
    paint(img, m, col)
    shadow(img, lambda d: d.ellipse(box(CX - 80, 150, CX + 80, 230), fill=255),
           shade(col, 0.45), 0.5, 12, into=m)
    shadow(img, lambda d: d.ellipse(box(CX - 50, 30, CX + 20, 90), fill=255),
           glow(col, 0.30), 0.40, 12, into=m)
    # kumas kivrimlari
    for pts in (
        [(CX - 62, 120), (CX - 58, 160), (CX - 50, 196)],
        [(CX + 60, 126), (CX + 56, 164), (CX + 48, 198)],
    ):
        ln = Image.new("L", (C, C), 0)
        ImageDraw.Draw(ln).line(P(spline(pts, closed=False, steps=10)), fill=255,
                                width=int(s(2.4)), joint="curve")
        paint(img, clip(soften(ln, 2), m), shade(col, 0.4), 0.45)
    # ortudan yuze dusen golge
    paint(img, clip(soften(m, 4), face), shade(skin, 0.6), 0.32)
    return m


def draw_cap(img, spec, hair, skin, face, hw, accent):
    """Beyzbol kepi: kepin altinda sac gorunur."""
    draw_hair(img, dict(vol=0.18, hl=66, fringe="round", side=spec.get("side", 0.44)),
              hair, skin, face, hw)
    # Basik ve genis kubbe: cok yuksek/yuvarlak olursa bere gibi duruyor.
    crown = [(CX - 60, 70), (CX - 61, 50), (CX - 36, 32), (CX, 27),
             (CX + 36, 32), (CX + 61, 50), (CX + 60, 70), (CX, 76)]
    m = mask_of(poly(crown))
    paint(img, m, accent)
    shadow(img, lambda d: d.ellipse(box(CX - 60, 48, CX + 60, 86), fill=255),
           darken(accent, 0.45), 0.5, 8, into=m)
    shadow(img, lambda d: d.ellipse(box(CX - 40, 18, CX + 10, 52), fill=255),
           lighten(accent, 0.35), 0.40, 9, into=m)
    # dikis cizgileri
    for dx in (-24, 0, 24):
        ln = Image.new("L", (C, C), 0)
        ImageDraw.Draw(ln).line(P(spline([(CX + dx * 0.35, 24), (CX + dx, 46),
                                          (CX + dx * 1.25, 68)],
                                         closed=False, steps=8)),
                                fill=255, width=int(s(1.2)), joint="curve")
        paint(img, clip(soften(ln, 1), m), darken(accent, 0.35), 0.5)
    # siperlik: one dogru tasan, alti belirgin koyu
    brim = [(CX - 64, 66), (CX - 48, 82), (CX - 16, 89), (CX + 18, 88),
            (CX + 50, 80), (CX + 64, 65), (CX + 56, 60), (CX, 63), (CX - 56, 60)]
    bm = mask_of(poly(brim))
    paint(img, bm, darken(accent, 0.26))
    shadow(img, lambda d: d.ellipse(box(CX - 66, 72, CX + 66, 94), fill=255),
           darken(accent, 0.58), 0.65, 4, into=bm)
    shadow(img, lambda d: d.ellipse(box(CX - 60, 58, CX + 60, 70), fill=255),
           lighten(accent, 0.25), 0.35, 4, into=bm)
    paint(img, mask_of(lambda d: d.ellipse(circ(CX, 29, 4.5), fill=255)),
          darken(accent, 0.3))
    # siperligin yuze dusurdugu golge
    shadow(img, lambda d: d.ellipse(box(CX - 56, 60, CX + 56, 96), fill=255),
           shade(skin, 0.7), 0.30, 6, into=face)


def draw_beanie(img, spec, hair, skin, face, hw):
    draw_hair(img, dict(vol=0.16, hl=70, fringe="round", side=spec.get("side", 0.46)),
              hair, skin, face, hw)
    dome = [(CX - 58, 76), (CX - 60, 48), (CX - 34, 26), (CX, 20),
            (CX + 34, 26), (CX + 60, 48), (CX + 58, 76), (CX, 82)]
    m = mask_of(poly(dome))
    paint(img, m, hair)
    shadow(img, lambda d: d.ellipse(box(CX - 62, 56, CX + 62, 96), fill=255),
           shade(hair, 0.45), 0.45, 8, into=m)
    shadow(img, lambda d: d.ellipse(box(CX - 42, 18, CX + 6, 54), fill=255),
           glow(hair, 0.35), 0.35, 10, into=m)
    # orgu cizgileri
    for dx in range(-48, 49, 16):
        ln = Image.new("L", (C, C), 0)
        ImageDraw.Draw(ln).line(P([(CX + dx * 0.55, 24), (CX + dx, 76)]),
                                fill=255, width=int(s(1.3)), joint="curve")
        paint(img, clip(soften(ln, 1.2), m), shade(hair, 0.35), 0.35)
    # kivrim (kas cizgisinin USTUNDE kalmali - asagi kayarsa goz bandi gibi durur)
    cuff = mask_of(lambda d: d.rounded_rectangle(
        box(CX - 60, 64, CX + 60, 84), radius=s(9), fill=255))
    paint(img, cuff, mix(hair, shade(hair, 0.3), 0.6))
    shadow(img, lambda d: d.rectangle(box(CX - 62, 78, CX + 62, 88), fill=255),
           shade(hair, 0.5), 0.5, 3, into=cuff)
    shadow(img, lambda d: d.rectangle(box(CX - 62, 64, CX + 62, 70), fill=255),
           glow(hair, 0.25), 0.35, 3, into=cuff)
    shadow(img, lambda d: d.ellipse(box(CX - 56, 78, CX + 56, 104), fill=255),
           shade(skin, 0.65), 0.28, 5, into=face)


def draw_beard(img, hair, skin, face, head, hw, v):
    """Sakal: cene hattini takip eder, ust siniri yumusak."""
    dark = mix(hair, (0x12, 0x0E, 0x10), 0.35)
    lower = [(x, y) for x, y in head if y > 104]
    if not lower:
        return
    grown = [(CX + (x - CX) * 1.03, HEAD_MID + (y - HEAD_MID) * 1.04) for x, y in lower]
    # Ust sinir favorilerden (saca baglanacak kadar yukaridan) baslayip
    # biyik bandina iner; merkez y=130 ki ust dudakla arasinda biyik kalsin.
    top_cut = spline([(CX - hw(104) - 1, 101), (CX - 42, 124), (CX - 18, 136),
                      (CX, 130), (CX + 18, 136), (CX + 42, 124),
                      (CX + hw(104) + 1, 101)],
                     closed=False, steps=12)
    # grown sagdan basliyor, cenede donup solda bitiyor; kapanis egrisi de
    # soldan saga gitmeli - ters cevirirsek poligon kendini kesiyor.
    pts = grown + top_cut
    m = mask_of(lambda d: d.polygon(P(pts), fill=255))
    # AGIZ BOSLUGU: sakal dudaklari yutmamali (yoksa cenede maske gibi duruyor).
    w = 15.0 * v["lips"]
    hole = soften(mask_of(lambda d: d.ellipse(
        box(CX - w - 2.0, MOUTH_Y - 5, CX + w + 2.0, MOUTH_Y + 9), fill=255)), 1.6)
    m = ImageChops.subtract(m, hole)
    m = soften(m, 1.2)
    paint(img, m, mix(hair, dark, 0.35), 0.97)
    shadow(img, lambda d: d.ellipse(box(CX - 44, 150, CX + 44, 190), fill=255),
           dark, 0.5, 8, into=m)
    shadow(img, lambda d: d.ellipse(box(CX - 40, 120, CX + 40, 146), fill=255),
           glow(hair, 0.2), 0.25, 8, into=m)
    # biyik
    mus = [(CX - 17, MOUTH_Y - 7), (CX - 7, MOUTH_Y - 11), (CX, MOUTH_Y - 9),
           (CX + 7, MOUTH_Y - 11), (CX + 17, MOUTH_Y - 7),
           (CX + 12, MOUTH_Y - 2), (CX, MOUTH_Y - 4), (CX - 12, MOUTH_Y - 2)]
    paint(img, soften(mask_of(poly(mus)), 0.8), mix(hair, dark, 0.3), 0.95)


# ------------------------------------------------------------ aksesuar ----
def draw_glasses(img, skin, face, v):
    lens_w, lens_h = 19.0, 16.0
    for side in (-1, 1):
        lx = CX + side * EYE_DX
        rect = box(lx - lens_w / 2, EYE_Y - lens_h / 2 - 1,
                   lx + lens_w / 2, EYE_Y + lens_h / 2 - 1)
        lens = mask_of(lambda d, r=rect: d.rounded_rectangle(r, radius=s(6.5), fill=255))
        paint(img, lens, (0xDC, 0xEA, 0xF2), 0.20)
        # camda capraz parlama
        paint(img, clip(mask_of(lambda d, l=lx: d.polygon(P([
            (l - 11, EYE_Y + 8), (l - 3, EYE_Y - 10),
            (l + 2, EYE_Y - 10), (l - 6, EYE_Y + 8)]), fill=255)), lens),
            WHITE, 0.30)
        ring = Image.new("L", (C, C), 0)
        ImageDraw.Draw(ring).rounded_rectangle(rect, radius=s(6.5), outline=255,
                                               width=int(s(1.9)))
        paint(img, ring, FRAME, 0.92)
        # sap
        arm = Image.new("L", (C, C), 0)
        ImageDraw.Draw(arm).line(P([(lx + side * lens_w / 2, EYE_Y - 3),
                                    (CX + side * 54, EYE_Y - 5)]),
                                 fill=255, width=int(s(1.8)))
        paint(img, arm, FRAME, 0.85)
    bridge = Image.new("L", (C, C), 0)
    ImageDraw.Draw(bridge).line(P([(CX - EYE_DX + 9.5, EYE_Y - 4),
                                   (CX, EYE_Y - 6), (CX + EYE_DX - 9.5, EYE_Y - 4)]),
                                fill=255, width=int(s(1.8)), joint="curve")
    paint(img, bridge, FRAME, 0.9)
    # cerceve golgesi
    shadow(img, lambda d: d.rounded_rectangle(
        box(CX - 46, EYE_Y + 5, CX + 46, EYE_Y + 11), radius=s(4), fill=255),
        shade(skin, 0.6), 0.22, 3.5, into=face)


def draw_earrings(img, hw):
    for side in (-1, 1):
        x = CX + side * (hw(118) + 1)
        paint(img, mask_of(lambda d, X=x: d.ellipse(circ(X, 122, 4.2), fill=255)), GOLD)
        paint(img, mask_of(lambda d, X=x: d.ellipse(circ(X - 1.2, 120.6, 1.5), fill=255)),
              lighten(GOLD, 0.6), 0.9)


def draw_necklace(img):
    chain = Image.new("L", (C, C), 0)
    ImageDraw.Draw(chain).line(P(spline([(CX - 30, 196), (CX - 18, 210),
                                         (CX, 214), (CX + 18, 210), (CX + 30, 196)],
                                        closed=False, steps=12)),
                               fill=255, width=int(s(1.8)), joint="curve")
    paint(img, chain, GOLD)
    paint(img, mask_of(lambda d: d.ellipse(circ(CX, 219, 5.5), fill=255)), GOLD)
    paint(img, mask_of(lambda d: d.ellipse(circ(CX - 1.6, 217.4, 2.0), fill=255)),
          lighten(GOLD, 0.6), 0.9)


def draw_headband(img, col, hw):
    band = mask_of(lambda d: d.polygon(P(spline([
        (CX - hw(72) - 3, 74), (CX - 26, 62), (CX, 59), (CX + 26, 62),
        (CX + hw(72) + 3, 74), (CX + hw(72) + 1, 83), (CX, 69),
        (CX - hw(72) - 1, 83)], steps=12)), fill=255))
    paint(img, band, col)
    shadow(img, lambda d: d.rectangle(box(CX - 60, 76, CX + 60, 88), fill=255),
           darken(col, 0.4), 0.45, 3, into=band)
    shadow(img, lambda d: d.rectangle(box(CX - 60, 58, CX + 60, 66), fill=255),
           lighten(col, 0.4), 0.4, 3, into=band)


def draw_bow(img, col):
    """Sac tokasi: iki ilmek + ortada dugum. Basin YANINA oturur - tepeye iki
    ucgen koyulursa kedi kulagi gibi duruyor."""
    bx, by = CX - 46, 62
    for side in (-1, 1):
        loop = mask_of(poly([
            (bx + side * 3, by),
            (bx + side * 15, by - 10),
            (bx + side * 20, by + 1),
            (bx + side * 13, by + 9),
        ], steps=12))
        paint(img, loop, col)
        shadow(img, lambda d, sd=side: d.ellipse(
            box(bx + sd * 4, by + 2, bx + sd * 20, by + 12), fill=255),
            darken(col, 0.40), 0.55, 2.5, into=loop)
        shadow(img, lambda d, sd=side: d.ellipse(
            box(bx + sd * 6, by - 11, bx + sd * 18, by - 2), fill=255),
            lighten(col, 0.35), 0.40, 2.5, into=loop)
    # kurdele uclari
    paint(img, mask_of(poly([(bx - 2, by + 3), (bx - 9, by + 17), (bx - 1, by + 14),
                             (bx + 4, by + 18), (bx + 3, by + 3)], steps=10)),
          darken(col, 0.12))
    paint(img, mask_of(lambda d: d.ellipse(circ(bx, by, 4.6), fill=255)),
          darken(col, 0.22))
    paint(img, mask_of(lambda d: d.ellipse(circ(bx - 1.4, by - 1.4, 1.8), fill=255)),
          lighten(col, 0.45), 0.8)


def draw_freckles(img, skin, face):
    col = shade(skin, 0.42)
    spots = [(-30, 124, 1.9), (-23, 130, 1.6), (-36, 131, 1.5), (-27, 136, 1.4),
             (30, 124, 1.9), (23, 130, 1.6), (36, 131, 1.5), (27, 136, 1.4),
             (-8, 128, 1.3), (8, 128, 1.3)]
    for dx, y, r in spots:
        shadow(img, lambda d, X=dx, Y=y, R=r: d.ellipse(circ(CX + X, Y, R), fill=255),
               col, 0.5, 0.7, into=face)


# ------------------------------------------------------- yuz varyasyonu ----
def variants(i, gender):
    """Her karaktere kendi yuz DNA'si - 49 avatar ayni surattan ibaret olmasin.

    Indeksten deterministik turetilir (tekrar calistirinca ayni sonuc)."""
    fem = gender == "k"
    return dict(
        jaw=(0.93 if fem else 1.06) + 0.035 * ((i % 3) - 1),
        chin=(0.95 if fem else 1.03) + 0.03 * ((i % 4) - 1.5),
        cheek=1.0 + 0.022 * ((i % 5) - 2),
        eye_w=1.0 + 0.045 * ((i % 4) - 1.5),
        eye_h=(1.07 if fem else 0.95) + 0.045 * ((i % 3) - 1),
        brow=(0.78 if fem else 1.22) + 0.10 * ((i % 4) - 1.5),
        brow_arch=(1.25 if fem else 0.95) + 0.20 * ((i % 3) - 1),
        nose=(0.92 if fem else 1.07) + 0.045 * ((i % 5) - 2),
        lips=(1.16 if fem else 0.93) + 0.05 * ((i % 4) - 1.5),
        smile=0.55 + 0.14 * ((i % 3) - 1) + (0.10 if fem else 0.0),
        teeth=(i % 3 == 0),
        lash=fem,
        eye_color=EYE_COLORS[i % len(EYE_COLORS)],
    )


EYE_COLORS = [
    (0x4A, 0x2E, 0x1C),
    (0x6B, 0x44, 0x23),
    (0x3F, 0x6E, 0x96),
    (0x4F, 0x7A, 0x52),
    (0x8C, 0x6B, 0x3F),
]


# --- Karakter tanimlari ------------------------------------------------------
# (cinsiyet, sac_stili, sac_rengi, ten, arkaplan, aksesuar)
CHARACTERS = [
    # --- Erkek (12) ---
    ("e", "kisa", "koyu_kahve", 0, 0, None),
    ("e", "dikenli", "siyah", 1, 3, None),
    ("e", "yandan_ayrik", "kahve", 0, 1, "gozluk"),
    ("e", "kisa", "siyah", 3, 5, "sakal"),
    ("e", "kivircik", "siyah", 4, 6, None),
    ("e", "sapka", "koyu_kahve", 1, 2, None),
    ("e", "dikenli", "sari", 0, 4, None),
    ("e", "kisa", "kizil", 1, 7, "cil"),
    ("e", "yandan_ayrik", "siyah", 2, 0, None),
    ("e", "kisa", "gri", 0, 3, "gozluk"),
    ("e", "kivircik", "kahve", 2, 5, "sakal"),
    ("e", "sapka", "siyah", 3, 6, None),
    # --- Kiz (12) ---
    ("k", "uzun", "siyah", 0, 4, None),
    ("k", "atkuyrugu", "kahve", 1, 0, "kupe"),
    ("k", "topuz", "koyu_kahve", 2, 1, None),
    ("k", "iki_orgu", "siyah", 3, 5, "fiyonk"),
    ("k", "bob", "sari", 0, 6, None),
    ("k", "basortu", "kizil", 1, 2, None),
    ("k", "uzun", "sari", 0, 3, "gozluk"),
    ("k", "atkuyrugu", "siyah", 4, 7, None),
    ("k", "topuz", "kizil", 0, 5, "cil"),
    ("k", "iki_orgu", "kahve", 2, 4, "kupe"),
    ("k", "bob", "siyah", 3, 1, None),
    ("k", "basortu", "koyu_kahve", 2, 6, "gozluk"),
    # --- Yeni karakterler (25) - yeni sac stilleri + yeni aksesuar/palet ---
    # Erkek (12)
    ("e", "dagınık", "koyu_kahve", 5, 8, None),
    ("e", "bere", "gri", 1, 9, None),
    ("e", "kel", "beyaz", 2, 3, "gozluk"),
    ("e", "yandan_ayrik", "bakir", 0, 5, None),
    ("e", "kisa", "siyah", 5, 2, "kolye"),
    ("e", "dikenli", "kizil", 1, 9, "cil"),
    ("e", "sapka", "gri", 3, 0, None),
    ("e", "kivircik", "bakir", 2, 6, None),
    ("e", "bere", "siyah", 0, 4, "sakal"),
    ("e", "dagınık", "kahve", 1, 7, "gozluk"),
    ("e", "kel", "koyu_kahve", 4, 1, None),
    ("e", "yandan_ayrik", "siyah", 5, 3, "sakal"),
    # Kiz (13)
    ("k", "uzun_dalgali", "sari", 0, 4, None),
    ("k", "yarim_topuz", "kahve", 1, 5, "kupe"),
    ("k", "tek_orgu", "siyah", 2, 6, None),
    ("k", "dagınık", "kizil", 0, 8, "cil"),
    ("k", "bere", "beyaz", 3, 2, None),
    ("k", "basortu", "bakir", 4, 9, "gozluk"),
    ("k", "uzun_dalgali", "koyu_kahve", 5, 1, "kolye"),
    ("k", "yarim_topuz", "gri", 2, 7, None),
    ("k", "atkuyrugu", "bakir", 0, 9, "sacbandi"),
    ("k", "bob", "beyaz", 1, 3, "fiyonk"),
    ("k", "tek_orgu", "kahve", 3, 0, "sacbandi"),
    ("k", "topuz", "siyah", 5, 8, "kupe"),
    ("k", "uzun_dalgali", "kizil", 2, 5, None),
]


def render(character, index):
    gender, hair_style, hair_name, skin_idx, bg_idx, extra = character
    skin = SKINS[skin_idx]
    hair = HAIRS[hair_name]
    bg = BGS[bg_idx]
    cloth = darken(bg, 0.32)
    v = variants(index, gender)
    spec = HAIR_SPECS[hair_style]
    kind = spec.get("kind", "hair")

    img = background(bg)
    head = spline(head_points(v))
    face = mask_of(lambda d: d.polygon(P(head), fill=255))
    hw = width_fn(head)

    # arka sac govdeden once (omuzlarin arkasinda kalir)
    if kind == "hair":
        draw_back_hair(img, spec, hair, hw)

    draw_body(img, cloth)
    draw_neck(img, skin, face)
    # Kulak yalnizca sacin altindan gorunecekse cizilir; uzun sac / basortusu
    # kulagi kapatir, yine de cizersek kenardan cikinti gibi duruyor.
    if kind != "scarf" and spec.get("side", 0.3) < 0.8:
        draw_ears(img, skin, hw, v)
    draw_face(img, skin, head, face, v)

    draw_brows(img, v, hair if kind != "scarf" else HAIRS["koyu_kahve"], face)
    draw_eyes(img, v, skin, v["eye_color"], v["lash"], face)
    draw_nose(img, v, skin, face)
    draw_mouth(img, v, skin, face)
    draw_blush(img, skin, face, 0.55 if gender == "k" else 0.35)

    if extra == "sakal":
        draw_beard(img, hair, skin, face, head, hw, v)
    if extra == "cil":
        draw_freckles(img, skin, face)

    if kind == "bald":
        draw_bald(img, skin, face)
    elif kind == "scarf":
        draw_scarf(img, hair, skin, face, hw)
    elif kind == "cap":
        draw_cap(img, spec, hair, skin, face, hw, lighten(cloth, 0.45))
    elif kind == "beanie":
        draw_beanie(img, spec, hair, skin, face, hw)
    else:
        draw_hair(img, spec, hair, skin, face, hw)

    if extra == "gozluk":
        draw_glasses(img, skin, face, v)
    elif extra == "kupe":
        draw_earrings(img, hw)
    elif extra == "fiyonk":
        draw_bow(img, lighten(bg, 0.45))
    elif extra == "kolye":
        draw_necklace(img)
    elif extra == "sacbandi":
        draw_headband(img, lighten(cloth, 0.5), hw)

    return img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    for i, character in enumerate(CHARACTERS, start=1):
        path = os.path.join(OUT_DIR, "avatar_char_%02d.png" % i)
        render(character, i).save(path, "PNG", optimize=True)
        size = os.path.getsize(path)
        total += size
        print("%s  %5.1f KB" % (os.path.basename(path), size / 1024))
    print("toplam %d avatar, %.2f MB -> %s"
          % (len(CHARACTERS), total / 1024 / 1024, OUT_DIR))


if __name__ == "__main__":
    main()
