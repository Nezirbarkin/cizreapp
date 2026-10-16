#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Kazima betiklerinin ortak kismi: gorselleri indirir, Urun Gorsel Kutuphanesi
toplu yukleme betiginin (scripts/upload_product_image_library.py) bekledigi
bicimde yazar:

    <cikti>/
      <Klasör>/<Ürün adı>.jpg
      kelimeler.csv     dosya;ad;kelimeler
      urunler.json      ham bilgi; yuklemede kullanilmaz

Kullanan betikler: scrape_migros_category.py, scrape_cagri_category.py.
"""

import concurrent.futures
import csv
import io
import json
import os
import re
import sys
import threading
import time
import unicodedata

from PIL import Image

from upload_product_image_library import fold, slug

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/128.0 Safari/537.36"
    ),
    "Accept-Language": "tr-TR,tr;q=0.9",
}
WORKERS = 3

try:
    sys.stdout.reconfigure(errors="replace")
    sys.stderr.reconfigure(errors="replace")
except AttributeError:
    pass


def safe_file_name(name):
    """Windows'ta gecersiz karakterleri ayiklar; basligin tam hali CSV'de kalir."""
    s = unicodedata.normalize("NFC", name)
    s = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', " ", s)
    s = re.sub(r"\s+", " ", s).strip().rstrip(". ")
    return s[:150] or "urun"


def join_keywords(names, skip=()):
    """Bos ve tekrar edenleri (Turkce harf duyarsiz) atip virgulle birlestirir."""
    out, seen = [], {fold(s) for s in skip}
    for n in names:
        n = (n or "").strip()
        if n and fold(n) not in seen:
            seen.add(fold(n))
            out.append(n)
    return ", ".join(out)


def save_library(session, rows, out_root, folder, size, source, no_image=(), delay=0.0):
    """rows: [{"name", "keywords", "image", "key", ...ek bilgi}] -> diske yazar.

    "key" (urun kodu) yalniz iki baslik ayni dosya kimligine dustugunde ada eklenir:
    yukleme betigi kimligi slug(dosya adi)'ndan uretir.
    Yarida kalirsa ayni cagri kaldigi yerden devam eder (diskteki gorsel atlanir).
    delay > 0: gorseller tek tek, her indirmeden once bu kadar saniye beklenerek
    indirilir (robots.txt Crawl-delay'i olan siteler icin).
    """
    folder = safe_file_name(folder)
    out_dir = os.path.join(out_root, folder)
    os.makedirs(out_dir, exist_ok=True)

    used = set()
    for r in rows:
        r["name"] = re.sub(r"\s+", " ", r["name"]).strip()
        stem = safe_file_name(r["name"])
        if slug(stem) in used:
            stem = safe_file_name(f"{r['name']} {r['key']}")
        used.add(slug(stem))
        r["file"] = stem + ".jpg"

    lock = threading.Lock()
    done, skipped, failed = [0], [0], []

    def fetch(row):
        target = os.path.join(out_dir, row["file"])
        if os.path.exists(target) and os.path.getsize(target) > 0:
            return "have"
        if delay:
            time.sleep(delay)
        for attempt in range(3):
            try:
                r = session.get(row["image"], headers={"User-Agent": HEADERS["User-Agent"]}, timeout=60)
                r.raise_for_status()
                im = Image.open(io.BytesIO(r.content))
                if im.mode in ("RGBA", "LA", "P"):
                    im = im.convert("RGBA")
                    bg = Image.new("RGB", im.size, (255, 255, 255))
                    bg.paste(im, mask=im.split()[-1])
                    im = bg
                else:
                    im = im.convert("RGB")
                im.thumbnail((size, size), Image.LANCZOS)
                tmp = target + ".part"
                im.save(tmp, "JPEG", quality=90, optimize=True)
                os.replace(tmp, target)
                return "new"
            except Exception:  # noqa: BLE001 — tekrar dene, sonra raporla
                if attempt == 2:
                    raise
                time.sleep(2 * (attempt + 1))

    workers = 1 if delay else WORKERS
    pace = f"tek tek, {delay:g} sn arayla" if delay else f"{workers} paralel"
    print(f"{len(rows)} görsel indiriliyor ({pace}) -> {out_dir}")
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(fetch, row): row for row in rows}
        for fut in concurrent.futures.as_completed(futures):
            row = futures[fut]
            with lock:
                try:
                    if fut.result() == "have":
                        skipped[0] += 1
                    else:
                        done[0] += 1
                except Exception as e:  # noqa: BLE001
                    failed.append((row["name"], str(e)[:200]))
                n = done[0] + skipped[0] + len(failed)
                if n % (10 if delay else 50) == 0 or n == len(rows):
                    print(f"  görsel {n}/{len(rows)}")

    ok_files = {r["file"] for r in rows if os.path.exists(os.path.join(out_dir, r["file"]))}
    with open(os.path.join(out_root, "kelimeler.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["dosya", "ad", "kelimeler"])
        for r in rows:
            if r["file"] in ok_files:
                w.writerow([f"{folder}/{r['file']}", r["name"], r["keywords"]])
    with open(os.path.join(out_root, "urunler.json"), "w", encoding="utf-8") as f:
        json.dump(
            {"kaynak": source, "klasor": folder, "urunler": rows},
            f, ensure_ascii=False, indent=1,
        )

    print()
    print(f"Tamamlandı: {done[0]} yeni, {skipped[0]} zaten vardı, {len(failed)} hata, "
          f"{len(no_image)} görselsiz ürün")
    print(f"Çıktı: {out_root}")
    for name, err in failed[:30]:
        print(f"  - {name}: {err}")
    for name in list(no_image)[:30]:
        print(f"  - görsel yok: {name}")
    if failed:
        print("Aynı komutu tekrar çalıştırınca yalnız eksikler indirilir.")
        sys.exit(1)
