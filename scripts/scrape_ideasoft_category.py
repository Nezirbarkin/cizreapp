#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""IdeaSoft altyapili magazanin kategori sayfasindaki urunlerin gorsel + basliklarini indirir
(ornek: onlinehirdavat.com).

Cikti, Urun Gorsel Kutuphanesi toplu yukleme betiginin
(scripts/upload_product_image_library.py) bekledigi bicimdedir (bkz. scrape_common.py):

    build/kazim_<site>_<kategori>/
      Hırdavat/WD40 Pas Sökücü Koruyucu Yağlayıcı Sprey.jpg
      kelimeler.csv     dosya;ad;kelimeler  (kelimeler = marka)
      urunler.json

Kullanim:
    python scripts/scrape_ideasoft_category.py https://www.onlinehirdavat.com/kategori/hirdavat --klasor "Hırdavat"

Secenekler: --klasor, --cikti, --boyut (scrape_migros_category.py ile ayni);
    --bekle SN   istekler arasi bekleme. Verilmezse sitenin robots.txt'indeki
                 Crawl-delay kullanilir (onlinehirdavat.com: 30 sn; ~540 urun ~4,5 saat).

Liste sunucuda HTML olarak gelir (?tp=N, 60'li). Sayfadaki gorsel kucuk halidir
(<ad>_min.jpg); buyugu ayni adres "_min" olmadan (1080 px).
Yarida kalirsa ayni komut kaldigi yerden devam eder (diskteki gorsel atlanir;
liste sayfalari yine gezilir).
"""

import argparse
import html
import os
import re
import sys
import time
import urllib.parse

import requests

from scrape_common import HEADERS, ROOT, join_keywords, safe_file_name, save_library
from upload_product_image_library import slug

DEFAULT_DELAY = 5.0


def get_text(session, url, tries=4):
    for attempt in range(tries):
        try:
            r = session.get(url, headers=HEADERS, timeout=60)
            if r.status_code == 200:
                return r.text
            if r.status_code not in (429, 500, 502, 503, 504):
                raise RuntimeError(f"HTTP {r.status_code}: {url}")
        except requests.RequestException:
            if attempt == tries - 1:
                raise
        time.sleep(10 * (attempt + 1))
    raise RuntimeError(f"Yanıt alınamadı: {url}")


def robots_delay(session, origin):
    """robots.txt'te "User-agent: *" grubunun Crawl-delay degeri (yoksa None)."""
    try:
        text = session.get(origin + "/robots.txt", headers=HEADERS, timeout=30).text
    except requests.RequestException:
        return None
    in_star = False
    for line in text.splitlines():
        key, _, value = line.partition(":")
        key, value = key.strip().lower(), value.strip()
        if key == "user-agent":
            in_star = value == "*"
        elif key == "crawl-delay" and in_star:
            try:
                return float(value)
            except ValueError:
                return None
    return None


def parse_listing(page):
    """Sayfadaki urun kartlari + son sayfa numarasi."""
    products = []
    for block in re.split(r'<div class="showcase">', page)[1:]:
        title = re.search(
            r'<div class="showcase-title">\s*<a href="([^"]+)"[^>]*>(.*?)</a>', block, re.S
        )
        image = re.search(r'data-src="([^"]+/myassets/products/[^"]+)"', block)
        if not title:
            continue
        brand = re.search(r'<div class="showcase-brand">\s*<a [^>]*>(.*?)</a>', block, re.S)
        products.append({
            "path": title.group(1),
            "name": html.unescape(re.sub(r"<[^>]+>", "", title.group(2))).strip(),
            "brand": html.unescape(brand.group(1)).strip() if brand else None,
            "thumb": image.group(1) if image else None,
        })
    pager = page[page.find('class="paginate"'):] if 'class="paginate"' in page else ""
    last = max([int(n) for n in re.findall(r"[?&]tp=(\d+)", pager)] or [1])
    return products, last


def full_image(thumb):
    """//host/.../ad_min.jpg?revision=1 -> https://host/.../ad.jpg?revision=1"""
    url = "https:" + thumb if thumb.startswith("//") else thumb
    return re.sub(r"_min(\.[A-Za-z0-9]+)(\?|$)", r"\1\2", url)


def main():
    ap = argparse.ArgumentParser(description="IdeaSoft kategorisinden görsel + başlık kazıma")
    ap.add_argument("adres")
    ap.add_argument("--klasor")
    ap.add_argument("--cikti")
    ap.add_argument("--boyut", type=int, default=1000)
    ap.add_argument("--bekle", type=float)
    args = ap.parse_args()

    u = urllib.parse.urlparse(args.adres)
    parts = u.path.strip("/").split("/")
    if len(parts) != 2 or parts[0] != "kategori":
        sys.exit("Beklenen adres: https://<site>/kategori/<kategori>")
    origin = f"{u.scheme or 'https'}://{u.netloc}"
    base = f"{origin}/kategori/{parts[1]}"
    session = requests.Session()

    delay = args.bekle
    if delay is None:
        crawl = robots_delay(session, origin)
        delay = crawl if crawl is not None else DEFAULT_DELAY
        print(f"Bekleme: {delay:g} sn" + (" (robots.txt Crawl-delay)" if crawl is not None else ""))

    time.sleep(delay)
    first = get_text(session, base)
    found, last = parse_listing(first)
    seen = {p["path"] for p in found}
    print(f"sayfa 1/{last}: {len(found)} ürün")
    heading = re.search(r'<div id="footer-content">\s*<h1>(.*?)</h1>', first, re.S)
    for tp in range(2, last + 1):
        time.sleep(delay)
        products, last_seen = parse_listing(get_text(session, f"{base}?tp={tp}"))
        last = max(last, last_seen)
        new = [p for p in products if p["path"] not in seen]
        seen.update(p["path"] for p in new)
        found.extend(new)
        print(f"sayfa {tp}/{last}: {len(products)} ürün, {len(new)} yeni (toplam {len(found)})")
    if not found:
        sys.exit("Ürün bulunamadı")

    folder = args.klasor or (html.unescape(heading.group(1)).strip() if heading else parts[1])
    site = slug(u.netloc.replace("www.", "").split(".")[0])
    out_root = os.path.abspath(
        args.cikti or os.path.join(ROOT, "build", f"kazim_{site}_{slug(parts[1])}")
    )

    rows, no_image = [], []
    for p in found:
        if not p["thumb"]:
            no_image.append(p["name"])
            continue
        rows.append({
            "name": p["name"],
            "keywords": join_keywords([p["brand"]], skip=[folder]),
            "image": full_image(p["thumb"]),
            "key": p["path"].rstrip("/").split("/")[-1],
            "brand": p["brand"],
            "url": origin + p["path"],
        })

    save_library(
        session, rows, out_root, safe_file_name(folder), args.boyut, args.adres, no_image,
        delay=delay,
    )


if __name__ == "__main__":
    main()
