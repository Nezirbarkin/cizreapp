#!/usr/bin/env python3
"""Bildirim panelindeki "şimdi çalıyor" kartının albüm kapağını üretir.

Neden bir betik: kapak, üçüncü parti bir görselden değil, uygulamanın kendi
renklerinden türetiliyor. Renk paleti değiştiğinde tasarımcı beklemeden
buradan yeniden üretilebilir.

Neden PNG (vektör değil): flutter_local_notifications largeIcon'u
`BitmapFactory.decodeResource` ile okur; VECTOR DRAWABLE burada `null` döner
ve kapak sessizce hiç görünmez. Bu yüzden gerçek bir raster dosya gerekir.

Neden saf stdlib: makinede Pillow yok. PNG, zlib + struct ile elle yazılıyor.

Kullanım:  python scripts/generate_music_art.py
Çıktı:     android/app/src/main/res/drawable-nodpi/ic_music_art.png
"""

import math
import struct
import zlib

OUT = "android/app/src/main/res/drawable-nodpi/ic_music_art.png"
SIZE = 512          # nihai boy
SS = 2              # süper örnekleme (kenar yumuşatma için)

ACCENT = (217, 26, 115)     # CizreApp pembesi
ACCENT_HI = (255, 104, 168)
BG_TOP = (26, 14, 46)
BG_BOTTOM = (58, 12, 58)
VINYL = (17, 16, 22)
GROOVE = (39, 37, 48)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def over(dst, src, alpha):
    """src'yi dst üzerine alpha ile yatırır."""
    return tuple(int(round(dst[i] * (1 - alpha) + src[i] * alpha)) for i in range(3))


def pixel(x, y, n):
    """(x, y) için renk. n = tuvalin kenar uzunluğu (süper örneklenmiş)."""
    cx = cy = n / 2.0
    dx, dy = x - cx, y - cy
    r = math.hypot(dx, dy)
    u = r / (n / 2.0)

    # 1) ZEMİN — köşegen degrade + merkezden yayılan aksan ışığı.
    c = lerp(BG_TOP, BG_BOTTOM, (x + y) / (2.0 * n))
    glow = max(0.0, 1.0 - (r / (n * 0.62)) ** 2)
    c = over(c, ACCENT, glow * 0.30)

    disc_r = n * 0.40
    label_r = n * 0.140

    # 2) PLAK — koyu disk + eşmerkezli oluklar.
    if r <= disc_r:
        c = VINYL
        if r > label_r:
            groove = (math.sin(r / (n / 96.0)) + 1) / 2
            c = over(c, GROOVE, 0.55 * groove)
        # Işık huzmesi: sol üstten sağ alta geçen yumuşak parlama.
        sheen = math.cos((dx * 0.7 + dy * 0.7) / (n * 0.30))
        if sheen > 0:
            c = over(c, (255, 255, 255), 0.055 * sheen ** 3)

    # 3) ETİKET — plağın ortasındaki renkli daire.
    if r <= label_r:
        c = lerp(ACCENT, ACCENT_HI, max(0.0, min(1.0, 0.5 + dy / (label_r * 2))))

        # "101" — üç blok: çubuk, halka, çubuk. Yazı tipi kullanılmıyor
        # (betik hiçbir fonta bağımlı olmamalı), biçimler geometrik.
        bar_w, bar_h = n * 0.0085, n * 0.060
        gap = n * 0.047
        ring_r, ring_w = n * 0.025, n * 0.011
        ink = None
        if abs(dy) <= bar_h / 2 and abs(abs(dx) - gap) <= bar_w:
            ink = (255, 255, 255)
        ring = math.hypot(dx, dy)
        if abs(ring - ring_r) <= ring_w / 2:
            ink = (255, 255, 255)
        if ink is not None:
            c = over(c, ink, 0.92)

    # 4) DIŞ KENAR — köşelere doğru hafif karartma (kart derinliği).
    if u > 0.85:
        c = over(c, (0, 0, 0), min(0.35, (u - 0.85) * 0.9))
    return c


def build():
    n = SIZE * SS
    rows = [[pixel(x + 0.5, y + 0.5, n) for x in range(n)] for y in range(n)]

    # Süper örneklemeyi geri indir (kutu filtresi).
    out = bytearray()
    for y in range(SIZE):
        out.append(0)  # PNG filtre baytı: yok
        for x in range(SIZE):
            r = g = b = 0
            for j in range(SS):
                for i in range(SS):
                    p = rows[y * SS + j][x * SS + i]
                    r += p[0]
                    g += p[1]
                    b += p[2]
            k = SS * SS
            out += bytes((r // k, g // k, b // k, 255))
    return bytes(out)


def chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def main():
    raw = build()
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(OUT, "wb") as f:
        f.write(png)
    print(f"{OUT} yazıldı ({len(png)} bayt)")


if __name__ == "__main__":
    main()
