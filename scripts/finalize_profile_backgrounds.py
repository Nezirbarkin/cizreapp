#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Hazir profil arka planlarini yayin bicimine getirir (Gorev 2.7).

Akis:
    1) $env:GEN_PROFILE_BACKGROUNDS='1'
       flutter test test/tools/generate_profile_backgrounds_test.dart
         -> build/profile_backgrounds/bg_NN.png (1600x900) + manifest.tsv
    2) python scripts/finalize_profile_backgrounds.py
         -> presets/bg_NN.jpg (1600x900, JPEG) ve thumbs/bg_NN.jpg (480x270)
            PROJE KOKUNDE (supabase storage cp goreli yol ister)
    3) npx supabase storage cp --linked --experimental -r presets ss:///profile-backgrounds
       npx supabase storage cp --linked --experimental -r thumbs  ss:///profile-backgrounds
       (sonra proje kokundeki presets/ ve thumbs/ silinir)

Kovadaki yollar `presets/bg_NN.jpg` ve `thumbs/bg_NN.jpg`; tablo
`profile_background_presets` bu yollari tutar (bkz. migration 20260928000001).
APPEND-ONLY: numara = sira; kapaklar dosya URL'sine bagli oldugundan kaydirilmaz.
"""

import glob
import os
import re
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, "build", "profile_backgrounds")
FULL_DIR = os.path.join(ROOT, "presets")
THUMB_DIR = os.path.join(ROOT, "thumbs")


def main():
    raws = sorted(
        glob.glob(os.path.join(RAW_DIR, "bg_*.png")),
        key=lambda p: int(re.search(r"bg_(\d+)", p).group(1)),
    )
    if not raws:
        sys.exit("Ham dosya yok: once flutter test ile uretin (bkz. dosya basi).")
    os.makedirs(FULL_DIR, exist_ok=True)
    os.makedirs(THUMB_DIR, exist_ok=True)
    full_total = thumb_total = 0
    for path in raws:
        name = os.path.splitext(os.path.basename(path))[0] + ".jpg"
        im = Image.open(path).convert("RGB")
        full = os.path.join(FULL_DIR, name)
        im.save(full, "JPEG", quality=84, optimize=True, progressive=True)
        thumb = os.path.join(THUMB_DIR, name)
        im.resize((480, 270), Image.LANCZOS).save(thumb, "JPEG", quality=80, optimize=True)
        full_total += os.path.getsize(full)
        thumb_total += os.path.getsize(thumb)
    print("%d arka plan: tam %.2f MB, kucuk %.2f MB" % (
        len(raws), full_total / 1024 / 1024, thumb_total / 1024 / 1024))


if __name__ == "__main__":
    main()
