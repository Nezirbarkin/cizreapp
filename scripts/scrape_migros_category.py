#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Migros kategori sayfasindaki (Sanal Market ya da Hemen) urunlerin gorsel + basliklarini indirir.

Cikti, Urun Gorsel Kutuphanesi toplu yukleme betiginin
(scripts/upload_product_image_library.py) bekledigi bicimdedir:

    build/kazim_<kategori>/
      Atıştırmalık/Tadım Bol Tuzlu Kavrulmuş Siyah Ayçekirdek 180 G.jpg
      kelimeler.csv     dosya;ad;kelimeler  (ad = sitedeki baslik, kelimeler = marka + kategoriler)
      urunler.json      ham bilgi (sku, marka, kategori, kaynak adres); yuklemede kullanilmaz

Kullanim:
    python scripts/scrape_migros_category.py https://www.migros.com.tr/hemen/atistirmalik-c-1125b
    python scripts/scrape_migros_category.py https://www.migros.com.tr/meyve-sebze-c-2 --klasor "Manav"
    python scripts/scrape_migros_category.py <adres> --klasor "Market" --cikti build/kazim_x

Secenekler:
    --klasor AD   Kutuphanedeki klasor adi (varsayilan: sitedeki kategori adi).
    --cikti YOL   Cikti klasoru (varsayilan build/kazim_<kategori>).
    --boyut N     Kaydedilen gorselin en uzun kenari (varsayilan 1000).
    --bekle SN    Liste sayfalari arasinda bekleme (varsayilan 0.5).

Yarida kalirsa ayni komut kaldigi yerden devam eder: diskte olan gorsel yeniden
indirilmez. Urun basina yalniz ilk (ana) gorsel alinir.
"""

import argparse
import os
import sys
import time
import urllib.parse

import requests

from scrape_common import HEADERS, ROOT, join_keywords, safe_file_name, save_library
from upload_product_image_library import slug

API_HEADERS = {**HEADERS, "Accept": "application/json"}


def get_json(session, url, tries=4):
    for attempt in range(tries):
        try:
            r = session.get(url, headers=API_HEADERS, timeout=40)
            if r.status_code == 200:
                return r.json()
            if r.status_code not in (429, 500, 502, 503, 504):
                raise RuntimeError(f"HTTP {r.status_code}: {url}")
        except requests.RequestException:
            if attempt == tries - 1:
                raise
        time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"Yanıt alınamadı: {url}")


def api_url(page_url):
    """Sayfa adresi -> (REST liste adresi, kategori slug'i, urun sayfasi on eki).

    Sanal Market: https://www.migros.com.tr/meyve-sebze-c-2
    Hemen:        https://www.migros.com.tr/hemen/atistirmalik-c-1125b
    """
    parts = urllib.parse.urlparse(page_url).path.strip("/").split("/")
    host = "https://www.migros.com.tr"
    if len(parts) == 2 and parts[0] == "hemen" and "-c-" in parts[1]:
        return f"{host}/rest/hemen/search/screens/{parts[1]}", parts[1], f"{host}/hemen/"
    if len(parts) == 1 and "-c-" in parts[0]:
        return f"{host}/rest/search/screens/{parts[0]}", parts[0], f"{host}/"
    sys.exit(
        "Beklenen adres: https://www.migros.com.tr/<kategori>-c-<kod> "
        "ya da https://www.migros.com.tr/hemen/<kategori>-c-<kod>"
    )


# Varsayilan "Önerilenler" sirasi istekler arasinda kayiyor (Hemen Atistirmalik'ta
# 971 urunun 20'si iki sayfada cikip 20'si hic gelmedi); fiyat siralari da esit
# fiyatlilarda kayiyor (Sanal Market Meyve-Sebze'de 200'de 195). Sitenin sundugu
# siralamalar sirayla denenir; turda tekrar yoksa ya da hepsi geldiyse durulur.
STABLE_SORTS = [
    "son-eklenenler", "once-en-dusuk-fiyat", "once-en-yuksek-fiyat", "cok-satanlar",
    "indirim-yuzdesine-gore", "indirim-miktarina-gore", "onerilenler",
]


def collect(session, base, wait):
    first = get_json(session, base + "?sayfa=1")["data"]["searchInfo"]
    offered = {c["requestParam"] for c in first.get("sortCriteria") or []}
    sorts = [s for s in STABLE_SORTS if s in offered] or [None]
    products, seen = [], set()
    for sort in sorts:
        url = base + (f"?sirala={sort}&sayfa=" if sort else "?sayfa=")
        info = get_json(session, url + "1")["data"]["searchInfo"]
        pages, hits = info["pageCount"], info["hitCount"]
        print(f"{hits} ürün, {pages} sayfa (sıralama: {sort or 'varsayılan'})")
        rows, pass_ids = 0, set()
        for page in range(1, pages + 1):
            if page > 1:
                time.sleep(wait)
                info = get_json(session, url + str(page))["data"]["searchInfo"]
            for p in info["storeProductInfos"]:
                rows += 1
                pass_ids.add(p["id"])
                if p["id"] not in seen:
                    seen.add(p["id"])
                    products.append(p)
            if page % 5 == 0 or page == pages:
                print(f"  liste {page}/{pages} ({len(products)} ürün)")
        # Turda hic tekrar yoksa sira sabittir, hepsi gelmistir.
        if rows == len(pass_ids) or len(products) >= hits:
            break
        print("  sıralama kaydı, eksikler başka sıralamayla tamamlanıyor")
    return products


def main():
    ap = argparse.ArgumentParser(description="Migros kategorisinden görsel + başlık kazıma")
    ap.add_argument("adres")
    ap.add_argument("--klasor")
    ap.add_argument("--cikti")
    ap.add_argument("--boyut", type=int, default=1000)
    ap.add_argument("--bekle", type=float, default=0.5)
    args = ap.parse_args()

    base, category_slug, product_prefix = api_url(args.adres)
    session = requests.Session()
    products = collect(session, base, args.bekle)
    if not products:
        sys.exit("Ürün bulunamadı")

    folder = args.klasor
    if not folder:
        for c in products[0].get("categoryAscendants") or []:
            if c.get("prettyName") == category_slug:
                folder = c["name"]
        folder = folder or category_slug.split("-c-")[0]
    out_root = os.path.abspath(
        args.cikti or os.path.join(ROOT, "build", "kazim_" + slug(category_slug.split("-c-")[0]))
    )

    rows, no_image = [], []
    for p in products:
        imgs = p.get("images") or []
        urls = imgs[0].get("urls", {}) if imgs else {}
        img = urls.get("PRODUCT_HD") or urls.get("PRODUCT_DETAIL")
        if not img:
            no_image.append(p["name"])
            continue
        brand = (p.get("brand") or {}).get("name")
        category = (p.get("category") or {}).get("name")
        rows.append({
            "name": p["name"],
            "keywords": join_keywords(
                [brand, category] + [c.get("name") for c in p.get("categoryAscendants") or []],
                skip=[folder],
            ),
            "image": img,
            "key": p.get("sku", p["id"]),
            "sku": p.get("sku"),
            "brand": brand,
            "category": category,
            "url": product_prefix + p.get("prettyName", ""),
        })

    save_library(session, rows, out_root, folder, args.boyut, args.adres, no_image)


if __name__ == "__main__":
    main()
