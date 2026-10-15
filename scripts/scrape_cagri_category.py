#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cagri Hipermarket (cagri.com) kategori sayfasindaki urunlerin gorsel + basliklarini indirir.

Cikti, Urun Gorsel Kutuphanesi toplu yukleme betiginin
(scripts/upload_product_image_library.py) bekledigi bicimdedir (bkz. scrape_common.py):

    build/kazim_cagri_<kategori>/
      Temel Gıda/Arbella Burgu Makarna 500 gr.jpg
      kelimeler.csv     dosya;ad;kelimeler  (kelimeler = marka + alt kategori)
      urunler.json

Kullanim:
    python scripts/scrape_cagri_category.py https://www.cagri.com/temel-gida
    python scripts/scrape_cagri_category.py <adres> --klasor "Market"

Secenekler: --klasor, --cikti, --boyut, --bekle (scrape_migros_category.py ile ayni).

Site Next.js; urun listesi sayfanin icindeki veri paketinde gelir (?sayfa=N, 48'li).
Ust kategorinin sirasi istekler arasinda kayiyor (1410 urunde 13 tekrar/eksik); alt
kategoriler kucuk ve sabit. Bu yuzden once her alt kategori gezilir (alt kategori adi
arama kelimesi olur), sonra yalniz ust kategoride duran urunler icin ust liste, yeni
urun gelmeyene kadar tekrar gezilir.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.parse

import requests

from scrape_common import HEADERS, ROOT, join_keywords, safe_file_name, save_library
from upload_product_image_library import fold, slug

HOST = "https://www.cagri.com"
IMAGE_HOST = "https://images.cagri.com/"
MAX_PARENT_PASSES = 4
_DEC = json.JSONDecoder()


def fetch_page(session, cat_slug, page, tries=4):
    """Kategori sayfasinin veri paketinden urun listesi nesnesini dondurur."""
    url = f"{HOST}/{cat_slug}?sayfa={page}"
    for attempt in range(tries):
        try:
            r = session.get(url, headers=HEADERS, timeout=40)
            if r.status_code == 200:
                break
            if r.status_code not in (429, 500, 502, 503, 504):
                raise RuntimeError(f"HTTP {r.status_code}: {url}")
        except requests.RequestException:
            if attempt == tries - 1:
                raise
        time.sleep(2 * (attempt + 1))
    else:
        raise RuntimeError(f"Yanıt alınamadı: {url}")
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)', r.text, re.S)
    blob = "".join(json.loads('"' + c + '"') for c in chunks)
    listing = None
    for m in re.finditer(r'\{"count":', blob):
        obj, _ = _DEC.raw_decode(blob, m.start())
        if "data" in obj:
            listing = obj
            break
    if listing is None:
        raise RuntimeError(f"Ürün listesi bulunamadı: {url}")
    title = re.search(r'\{"id":\d+,"description":"([^"]+)","slug":"' + re.escape(cat_slug) + '"', blob)
    listing["_title"] = title.group(1) if title else None
    return listing


def crawl(session, cat_slug, wait, seen, found, sub_name=None):
    """Kategorinin tum sayfalarini gezer; yeni urunleri found'a ekler.

    Dondurur: (ilk sayfa, sayfa sayisi, bu turda tekrar var mi, yeni urun sayisi).
    """
    first = fetch_page(session, cat_slug, 1)
    pages = max(1, -(-first["count"] // 48))
    rows, pass_ids, new = 0, set(), 0
    for page in range(1, pages + 1):
        listing = first if page == 1 else fetch_page(session, cat_slug, page)
        for p in listing["data"]:
            rows += 1
            pass_ids.add(p["id"])
            if p["id"] not in seen:
                seen.add(p["id"])
                p["_sub"] = sub_name
                found.append(p)
                new += 1
        if page < pages:
            time.sleep(wait)
    return first, pages, rows != len(pass_ids), new


def main():
    ap = argparse.ArgumentParser(description="Çağrı kategorisinden görsel + başlık kazıma")
    ap.add_argument("adres")
    ap.add_argument("--klasor")
    ap.add_argument("--cikti")
    ap.add_argument("--boyut", type=int, default=1000)
    ap.add_argument("--bekle", type=float, default=0.5)
    args = ap.parse_args()

    parts = urllib.parse.urlparse(args.adres).path.strip("/").split("/")
    if len(parts) != 1 or not parts[0]:
        sys.exit("Beklenen adres: https://www.cagri.com/<kategori>")
    cat_slug = parts[0]
    session = requests.Session()

    top = fetch_page(session, cat_slug, 1)
    total = top["count"]
    subs = top.get("categoryGroup") or []
    brands = sorted(
        (b["name"].strip() for b in top.get("brandGroup") or [] if b.get("name")),
        key=len, reverse=True,
    )
    print(f"{top['_title'] or cat_slug}: {total} ürün, {len(subs)} alt kategori")

    found, seen = [], set()
    for sub in subs:
        first, pages, shifted, new = crawl(session, sub["slug"], args.bekle, seen, found, sub["name"])
        if shifted:  # kucuk listede nadir; bir tur daha eksikleri toplar
            _, _, _, more = crawl(session, sub["slug"], args.bekle, seen, found, sub["name"])
            new += more
        print(f"  {sub['name']}: {first['count']} ürün, {new} yeni (toplam {len(found)})")
        time.sleep(args.bekle)

    for attempt in range(1, MAX_PARENT_PASSES + 1):
        _, pages, shifted, new = crawl(session, cat_slug, args.bekle, seen, found)
        print(f"  üst liste tur {attempt}: {new} yeni (toplam {len(found)}/{total})")
        if len(found) >= total or (attempt > 1 and new == 0) or not shifted:
            break

    if not found:
        sys.exit("Ürün bulunamadı")
    if len(found) < total:
        print(f"  uyarı: {total - len(found)} ürün listede hiç görünmedi")

    folder = args.klasor or top["_title"] or cat_slug
    out_root = os.path.abspath(
        args.cikti or os.path.join(ROOT, "build", "kazim_cagri_" + slug(cat_slug))
    )

    rows, no_image = [], []
    for p in found:
        images = sorted(p.get("images") or [], key=lambda i: i.get("sequence") or 0)
        if not images or not images[0].get("path"):
            no_image.append(p["name"])
            continue
        name_f = fold(p["name"])
        brand = next((b for b in brands if name_f.startswith(fold(b) + " ")), None)
        sub_words = re.split(r"\s*,\s*", p["_sub"]) if p["_sub"] else []
        rows.append({
            "name": p["name"],
            "keywords": join_keywords([brand] + sub_words, skip=[folder]),
            "image": IMAGE_HOST + images[0]["path"],
            "key": p.get("code") or p["id"],
            "code": p.get("code"),
            "brand": brand,
            "category": p["_sub"],
            "url": f"{HOST}/{(p.get('seo') or {}).get('slug', '')}",
        })

    save_library(session, rows, out_root, safe_file_name(folder), args.boyut, args.adres, no_image)


if __name__ == "__main__":
    main()
