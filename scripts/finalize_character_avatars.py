#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Kiz & erkek karakter avatarlarini yayin boyutuna getirir.

Akis (bkz. lib/features/profile/models/character_avatar_recipes.dart):

    1) $env:GEN_CHARACTER_AVATARS='1'
       flutter test test/tools/generate_character_avatars_test.dart
         -> build/avatar_raw/char_NN.png   (512 px, gercekci cizim motorundan)
    2) python scripts/finalize_character_avatars.py
         -> assets/avatars_characters/avatar_char_NN.png (320 px)

NEDEN AYRI ADIM: Flutter motoru tam boy cikti verir; burada LANCZOS ile
kucultup 256 renge indiriyoruz (Floyd-Steinberg). Gorsel fark gozle secilemiyor
ama dosya boyutu ~90 KB -> ~34 KB oluyor; 100 avatar ~3.4 MB tutuyor.

Dosya adi = tarifin sirasi (1'den). Kullanicilarin sectigi avatar_url dosya
adina bagli oldugu icin siralama degistirilmez, yeni karakter sona eklenir.
"""

import glob
import os
import re
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, "build", "avatar_raw")
OUT_DIR = os.path.join(ROOT, "assets", "avatars_characters")
SIZE = 320


def main():
    raws = sorted(
        glob.glob(os.path.join(RAW_DIR, "char_*.png")),
        key=lambda p: int(re.search(r"char_(\d+)", p).group(1)),
    )
    if not raws:
        sys.exit("Ham dosya yok: once flutter test ile uretin (bkz. dosya basi).")
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    for path in raws:
        n = int(re.search(r"char_(\d+)", path).group(1))
        im = Image.open(path).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
        q = im.quantize(256, method=Image.Quantize.MEDIANCUT,
                        dither=Image.Dither.FLOYDSTEINBERG)
        out = os.path.join(OUT_DIR, "avatar_char_%02d.png" % n)
        q.save(out, "PNG", optimize=True)
        total += os.path.getsize(out)
    print("%d avatar, %.2f MB -> %s" % (len(raws), total / 1024 / 1024, OUT_DIR))


if __name__ == "__main__":
    main()
