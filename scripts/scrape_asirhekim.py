#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Asir Hekim (asirhekim.com/urunlerimiz) urun gorsel + basliklarini indirir.

Cikti, Urun Gorsel Kutuphanesi toplu yukleme betiginin
(scripts/upload_product_image_library.py) bekledigi bicimdedir (bkz. scrape_common.py):

    build/kazim_asirhekim/
      Aktar/Dut pekmezi.jpg
      kelimeler.csv     dosya;ad;kelimeler  (kelimeler = marka + sitedeki kategori)
      urunler.json

Kullanim:
    python scripts/scrape_asirhekim.py
    python scripts/scrape_asirhekim.py --klasor "Aktar" --cikti build/kazim_asirhekim

Site React (Vite) tek sayfa uygulamasi; HTML bos gelir. Urun listesi JS paketinin
icinde sabit veri olarak durur:
    {name:"Kuruyemiş",brand:"...",description:"...",items:["Antep fıstığı",...]}
    {"Dut pekmezi":{src:<degisken>,alt:"Asır Hekim Dut Pekmezi kavanozu"}, Salep:{...}}
    <degisken>="/assets/dut-pekmezi-<hash>.jpg"
Gorseli yalniz eslemede adi gecen urunlerin var (2026-10-16: 175 baslikta 43); digerleri
sitede yalniz yazi karti oldugu icin "gorsel yok" diye raporlanir.
"""

import argparse
import os
import re
import sys

import requests

from scrape_common import HEADERS, ROOT, join_keywords, safe_file_name, save_library
from upload_product_image_library import fold, slug

HOST = "https://asirhekim.com"
PAGE = HOST + "/urunlerimiz/"

CATEGORY_RE = re.compile(
    r'\{name:"([^"]+)",brand:"([^"]*)",description:"[^"]*",items:\[([^\]]*)\]'
)
# Anahtar tirnakli ("Gold Kahve") ya da tek kelimeyse tirnaksiz (Salep) yazilir.
IMAGE_MAP_RE = re.compile(
    r'(?:"([^"]+)"|([^\W\d][\w]*)):\{src:([A-Za-z_$][\w$]*),alt:"([^"]*)"\}'
)
ASSET_RE = re.compile(r'([A-Za-z_$][\w$]*)="(/assets/[^"]+\.(?:jpe?g|png|webp))"')
# Bayilik kartlarindaki marka adlari (alt:"Qubo Coffee"); gorsel alt metninin basindaki
# marka bunlardan biriyse kelimelere o yazilir (kahveler "Asır Kuruyemiş" kategorisinde
# ama ambalaj Qubo Coffee).
LOGO_BRAND_RE = re.compile(r'\{brand:"[^"]+",type:"[^"]+",logo:[\w$]+,alt:"([^"]+)"')


def get(session, url):
    r = session.get(url, headers=HEADERS, timeout=90)
    r.raise_for_status()
    return r


def load_bundle(session):
    html = get(session, PAGE).text
    m = re.search(r'src="(/assets/index-[\w-]+\.js)"', html)
    if not m:
        sys.exit("Sayfada JS paketi bulunamadı; site yapısı değişmiş olabilir.")
    # Sunucu charset bildirmiyor; requests latin-1 sanar. Baytlari UTF-8 coz.
    return get(session, HOST + m.group(1)).content.decode("utf-8")


def parse(js):
    categories = []
    for name, brand, items in CATEGORY_RE.findall(js):
        categories.append((name, brand, re.findall(r'"([^"]+)"', items)))
    assets = dict(ASSET_RE.findall(js))
    images = []
    for quoted, bare, var, alt in IMAGE_MAP_RE.findall(js):
        if var in assets:
            images.append((quoted or bare, assets[var], alt))
    brands = sorted(set(LOGO_BRAND_RE.findall(js)), key=len, reverse=True)
    return categories, images, brands


def main():
    ap = argparse.ArgumentParser(description="Asır Hekim ürünlerinden görsel + başlık kazıma")
    ap.add_argument("--klasor", default="Aktar")
    ap.add_argument("--cikti")
    ap.add_argument("--boyut", type=int, default=1000)
    args = ap.parse_args()

    session = requests.Session()
    categories, images, brands = parse(load_bundle(session))
    if not categories or not images:
        sys.exit(f"Veri okunamadı (kategori {len(categories)}, görsel {len(images)}); "
                 "site yapısı değişmiş olabilir.")

    category_of = {}
    for cat_name, cat_brand, items in categories:
        for item in items:
            category_of.setdefault(fold(item), (cat_name, cat_brand))

    rows, seen = [], set()
    for name, path, alt in images:
        if fold(name) in seen:
            continue
        seen.add(fold(name))
        cat_name, cat_brand = category_of.get(fold(name), ("", ""))
        brand = next((b for b in brands if fold(alt).startswith(fold(b))), cat_brand)
        rows.append({
            "name": name,
            "keywords": join_keywords([brand, cat_name], skip=[name]),
            "image": HOST + path,
            "key": slug(name),
            "brand": brand,
            "category": cat_name,
            "alt": alt,
        })
    no_image = [
        f"{item} ({cat_name})"
        for cat_name, _, items in categories
        for item in items
        if fold(item) not in seen
    ]

    total = sum(len(items) for _, _, items in categories)
    print(f"{len(categories)} kategori, {total} başlık; {len(rows)} başlığın görseli var")
    for cat_name, _, items in categories:
        with_img = sum(1 for i in items if fold(i) in seen)
        print(f"  {cat_name}: {len(items)} başlık, {with_img} görselli")

    out_root = args.cikti or os.path.join(ROOT, "build", "kazim_asirhekim")
    save_library(session, rows, out_root, safe_file_name(args.klasor), args.boyut, PAGE, no_image)


if __name__ == "__main__":
    main()
