#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Urun Gorsel Kutuphanesine toplu gorsel yukler (2000+ gorsel icin).

Klasor yapisi (klasor adi = kutuphane klasoru, dosya adi = gorsel adi):

    kutuphane/
      Market/Pirinç Baldo.png
      Manav/Domates.png
      Manav/Salkım Domates.jpg
      Kozmetik/Şampuan 500 ml.webp
      kelimeler.csv        (istege bagli, bkz. asagi)

Kullanim:
    python scripts/upload_product_image_library.py kutuphane            # KURU: yalniz rapor
    python scripts/upload_product_image_library.py kutuphane --yukle    # gercekten yukler
    python scripts/upload_product_image_library.py kutuphane --sablon   # kelimeler.csv taslagi

Secenekler:
    --yukle        Yukle. Verilmezse hicbir sey yazilmaz, yalniz ne olacagi raporlanir.
    --pasif        Gorselleri PASIF ekle; admin panelinde (Pasif filtresi) kontrol edip
                   toplu "Yayina al" yaparsin. Verilmezse hemen yayinda.
    --sablon       Klasordeki tum gorseller icin kelimeler.csv taslagi uretir (Excel'de
                   acilir; ad ve arama kelimelerini doldurursun). Yukleme yapmaz.
    --boyut N      En uzun kenar piksel (varsayilan 800; kucukler buyutulmez).
    --kalite N     WebP kalitesi 1-100 (varsayilan 82).

kelimeler.csv (UTF-8, ';' ile ayrilmis; Excel'de "CSV UTF-8" olarak kaydet):
    dosya;ad;kelimeler
    Manav/Domates.png;Domates;sebze, kırmızı, salata
    Kozmetik/Şampuan 500 ml.webp;Şampuan;saç, banyo
  - "ad" bossa dosya adindan uretilir ("salkim_domates.png" -> "Salkim domates";
    Turkce karakterli dosya adi kullanmak daha iyidir).
  - "kelimeler" saticilarin arama kelimeleridir (gorsel adi zaten aranir).

Ne yapar:
  * Her gorseli acar, EXIF yonunu duzeltir, saydamligi beyaz zemine oturtur,
    en uzun kenari --boyut'a kucultur ve WebP'ye cevirir (tipik 30-80 KB; kova
    siniri 2 MB). Yapay zekanin 1024 px / 2-3 MB PNG'leri boylece sorunsuz yuklenir.
  * Storage: product-image-presets/library/<klasor>/<ad>-<icerik ozeti>.webp
  * Tablo: product_image_presets satiri; klasor yoksa product_image_folders'a eklenir.
  * Ayni gorsel iki kez EKLENMEZ: her gorselin kimligi (source_key) "<klasor>/<dosya
    adi>"nin uzantisiz, sadelestirilmis halidir ("Manav/Salkım Domates.png" ->
    "manav/salkim-domates"); kutuphanede varsa atlanir. Yarida kalan yukleme ayni
    komutla devam ettirilir. Gorsel adminde baska klasore tasinsa ya da CSV'de adi
    duzeltilse de kimligi degismez; ama DOSYA bilgisayarda yeniden adlandirilir ya da
    baska klasore konursa yeni gorsel sayilir.
  * Storage dosyalari ASLA silinmez/degistirilmez: urunler gorsel URL'sini kopyalar.
    Dosya yolu icerik ozeti tasidigi icin degisen gorsel yeni dosyaya yazilir.

Yetki: SUPABASE_SERVICE_ROLE_KEY ortam degiskeni ya da (yoksa) giris yapilmis Supabase
CLI'dan (`supabase projects api-keys`) alinir; anahtar ekrana basilmaz, diske yazilmaz.
Proje: SUPABASE_PROJECT_REF ya da supabase/.temp/project-ref.
"""

import argparse
import concurrent.futures
import csv
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

from PIL import Image, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUCKET = "product-image-presets"
MAX_BYTES = 2 * 1024 * 1024  # kova siniri
INPUT_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}
CSV_NAME = "kelimeler.csv"
WORKERS = 4

# Konsol cp1254 olabilir; Turkce harfler basilir, desteklenmeyen isaret '?' olur.
try:
    sys.stdout.reconfigure(errors="replace")
    sys.stderr.reconfigure(errors="replace")
except AttributeError:
    pass

# ---------------------------------------------------------------------------
# Metin yardimcilari
# ---------------------------------------------------------------------------

_TR = str.maketrans("ıİşŞğĞçÇöÖüÜ", "iIsSgGcCoOuU")
_JUNK = re.compile(
    r"^(img|dsc|pxl|image|screenshot|photo|foto|whatsapp|resim|unnamed)\b",
    re.IGNORECASE,
)


def fold(text):
    """public.search_normalize ile ayni: Turkce harf + aksan sadelestirme, kucuk harf."""
    s = unicodedata.normalize("NFKD", text.translate(_TR))
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    return s.lower()


def slug(text):
    """Storage yolu / kimlik icin: "Salkım Domates 1 kg" -> "salkim-domates-1-kg"."""
    s = re.sub(r"[^a-z0-9]+", "-", fold(text)).strip("-")
    return s or "gorsel"


def name_from_stem(stem):
    """Dosya adindan gorsel adi; anlamsiz adlarda (IMG_1234) bos doner."""
    s = re.sub(r"[_\-]+", " ", stem)
    s = re.sub(r"\s+", " ", s).strip()
    letters = len(re.findall(r"[A-Za-zÇĞİÖŞÜçğıöşü]", s))
    if not s or letters < 3 or _JUNK.match(s):
        return ""
    first = "İ" if s[0] == "i" else s[0].upper()
    return first + s[1:]


# ---------------------------------------------------------------------------
# Dosya tarama ve CSV
# ---------------------------------------------------------------------------


class Item:
    def __init__(self, folder_dir, path):
        self.folder_dir = folder_dir  # diskteki klasor adi
        self.path = path
        self.file = unicodedata.normalize("NFC", os.path.basename(path))
        self.stem = os.path.splitext(self.file)[0]
        self.rel = folder_dir + "/" + self.file
        self.name = name_from_stem(self.stem)
        self.keywords = None
        # Kimlik (source_key) DOSYA adindan: CSV'de ad duzeltilse de ayni gorsel
        # sayilir; uzanti yok sayilir (domates.png ile domates.webp ayni gorsel).
        self.key = slug(folder_dir) + "/" + slug(self.stem)
        self.order = 0


def scan(root, warnings):
    items = []
    for entry in sorted(os.listdir(root), key=fold):
        full = os.path.join(root, entry)
        if os.path.isfile(full):
            if entry.lower() != CSV_NAME and os.path.splitext(entry)[1].lower() in INPUT_EXTS:
                warnings.append(f"{entry}: kökte duruyor, bir klasöre koyun (atlandı)")
            continue
        folder = unicodedata.normalize("NFC", entry.strip())
        for sub in sorted(os.listdir(full), key=fold):
            sub_full = os.path.join(full, sub)
            if os.path.isdir(sub_full):
                warnings.append(f"{entry}/{sub}/: alt klasör desteklenmez (atlandı)")
                continue
            if os.path.splitext(sub)[1].lower() not in INPUT_EXTS:
                continue
            items.append(Item(folder, sub_full))
    return items


def read_csv(path, warnings):
    """{sadeleştirilmiş "klasör/dosya.png": (ad, kelimeler, yazıldığı hali)}."""
    raw = open(path, "rb").read()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = raw.decode("cp1254")
        warnings.append(
            f"{CSV_NAME} UTF-8 değil (Türkçe Windows kodlamasıyla okundu); "
            'Excel\'de "CSV UTF-8" olarak kaydetmeniz önerilir'
        )
    first = text.splitlines()[0] if text else ""
    delim = ";" if ";" in first else ("\t" if "\t" in first else ",")
    rows = list(csv.reader(io.StringIO(text), delimiter=delim))
    if not rows:
        return {}
    header = [fold(h.strip()) for h in rows[0]]
    try:
        i_file = header.index("dosya")
    except ValueError:
        sys.exit(f"{CSV_NAME}: ilk satırda 'dosya' sütunu yok (dosya;ad;kelimeler)")
    i_name = header.index("ad") if "ad" in header else None
    i_kw = header.index("kelimeler") if "kelimeler" in header else None
    def cell(row, i):
        return row[i].strip() if i is not None and i < len(row) else ""

    out = {}
    for row in rows[1:]:
        if not cell(row, i_file):
            continue
        original = unicodedata.normalize("NFC", cell(row, i_file).replace("\\", "/"))
        out[fold(original)] = (cell(row, i_name), cell(row, i_kw), original)
    return out


def write_template(root, items):
    target = os.path.join(root, CSV_NAME)
    if os.path.exists(target):
        target = os.path.join(root, "kelimeler_sablon.csv")
    with open(target, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["dosya", "ad", "kelimeler"])
        for it in items:
            w.writerow([it.rel, it.name, ""])
    return target


# ---------------------------------------------------------------------------
# Supabase (REST + Storage, service role)
# ---------------------------------------------------------------------------


class Supabase:
    def __init__(self):
        self.ref = os.environ.get("SUPABASE_PROJECT_REF") or self._read_ref()
        self.url = f"https://{self.ref}.supabase.co"
        self.key, self.jwt = self._key()

    @staticmethod
    def _read_ref():
        p = os.path.join(ROOT, "supabase", ".temp", "project-ref")
        if not os.path.exists(p):
            sys.exit("Proje bulunamadı: SUPABASE_PROJECT_REF verin ya da `supabase link` yapın")
        return open(p, encoding="utf-8").read().strip()

    def _key(self):
        env = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        if env:
            return env, env.startswith("eyJ")
        exe = shutil.which("supabase")
        cmd = [exe] if exe else [shutil.which("npx") or "npx", "supabase"]
        try:
            out = subprocess.run(
                cmd + ["projects", "api-keys", "--project-ref", self.ref, "-o", "json"],
                capture_output=True, text=True, encoding="utf-8", timeout=120,
            ).stdout
            keys = json.loads(out[out.index("["): out.rindex("]") + 1])
        except Exception:
            sys.exit(
                "Yetki anahtarı alınamadı. `supabase login` yapın ya da "
                "SUPABASE_SERVICE_ROLE_KEY ortam değişkenini verin."
            )
        by = {(k.get("name"), k.get("type")): k.get("api_key") for k in keys}
        legacy = by.get(("service_role", "legacy")) or by.get(("service_role", None))
        if legacy:
            return legacy, True
        secret = next((v for (n, t), v in by.items() if t == "secret" and v), None)
        if not secret:
            sys.exit("CLI çıktısında service_role / secret anahtar yok")
        return secret, False

    def _headers(self, extra=None):
        h = {"apikey": self.key}
        if self.jwt:
            h["Authorization"] = "Bearer " + self.key
        h.update(extra or {})
        return h

    def request(self, method, path, body=None, headers=None, raw=None):
        data = raw if raw is not None else (
            json.dumps(body).encode("utf-8") if body is not None else None
        )
        h = self._headers(headers)
        if raw is None and body is not None:
            h.setdefault("Content-Type", "application/json")
        req = urllib.request.Request(self.url + path, data=data, method=method, headers=h)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                text = r.read().decode("utf-8")
                return json.loads(text) if text.strip() else None
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:300]
            raise RuntimeError(f"HTTP {e.code}: {detail}") from None

    def rest_all(self, table, query):
        rows, offset = [], 0
        while True:
            page = self.request(
                "GET", f"/rest/v1/{table}?{query}&offset={offset}&limit=1000"
            )
            if not page:
                return rows
            rows.extend(page)
            offset += len(page)

    def upload(self, path, data):
        quoted = urllib.parse.quote(path)
        self.request(
            "POST", f"/storage/v1/object/{BUCKET}/{quoted}", raw=data,
            headers={
                "Content-Type": "image/webp",
                "Cache-Control": "max-age=31536000",
                # Yol içerik özeti taşır: aynı yol = aynı bayt; yarıda kalan
                # yüklemenin tekrarı güvenli.
                "x-upsert": "true",
            },
        )
        return f"{self.url}/storage/v1/object/public/{BUCKET}/{quoted}"


# ---------------------------------------------------------------------------
# Gorsel donusturme
# ---------------------------------------------------------------------------


def to_webp(path, size, quality):
    with open(path, "rb") as f:
        src = f.read()
    im = Image.open(io.BytesIO(src))
    im = ImageOps.exif_transpose(im)
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGB", im.size, (255, 255, 255))
        bg.paste(im, mask=im.split()[-1])
        im = bg
    else:
        im = im.convert("RGB")
    im.thumbnail((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "WEBP", quality=quality, method=6)
    return buf.getvalue(), hashlib.sha1(src).hexdigest()[:12], im.size


# ---------------------------------------------------------------------------
# Ana akis
# ---------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description="Ürün Görsel Kütüphanesine toplu yükleme")
    ap.add_argument("klasor", help="kök klasör (içinde Market/, Manav/ ... klasörleri)")
    ap.add_argument("--yukle", action="store_true", help="gerçekten yükle (yoksa kuru çalıştırma)")
    ap.add_argument("--pasif", action="store_true", help="görselleri pasif ekle")
    ap.add_argument("--sablon", action="store_true", help="kelimeler.csv taslağı üret")
    ap.add_argument("--boyut", type=int, default=800)
    ap.add_argument("--kalite", type=int, default=82)
    args = ap.parse_args()

    root = os.path.abspath(args.klasor)
    if not os.path.isdir(root):
        sys.exit(f"Klasör yok: {root}")
    if not (100 <= args.boyut <= 2000) or not (1 <= args.kalite <= 100):
        sys.exit("--boyut 100-2000, --kalite 1-100 arasında olmalı")

    warnings = []
    items = scan(root, warnings)
    if not items:
        sys.exit("Hiç görsel bulunamadı (kök/<klasör>/<görsel>.png yapısı bekleniyor)")

    if args.sablon:
        target = write_template(root, items)
        print(f"{len(items)} görsel için şablon yazıldı: {target}")
        print("Excel'de 'ad' ve 'kelimeler' sütunlarını doldurup kelimeler.csv olarak kaydedin.")
        return

    csv_path = os.path.join(root, CSV_NAME)
    meta = read_csv(csv_path, warnings) if os.path.exists(csv_path) else {}
    used_csv = set()
    for it in items:
        m = meta.get(fold(it.rel))
        if m:
            used_csv.add(fold(it.rel))
            if m[0]:
                it.name = m[0]
            it.keywords = m[1] or None
    # Görseller parça parça üretilirken CSV'de dosyası henüz olmayan çok satır olur:
    # tek tek değil, özet olarak bildir.
    unmatched = [meta[k][2] for k in sorted(meta.keys() - used_csv)]
    if unmatched:
        sample = ", ".join(f"'{u}'" for u in unmatched[:3])
        warnings.append(
            f"{CSV_NAME}: {len(unmatched)} satırın dosyası yok (henüz üretilmemiş ya da "
            f"adı farklı olabilir), ör. {sample}"
        )

    sb = Supabase()
    folders = sb.rest_all(
        "product_image_folders", "select=id,name,display_order,is_active&order=display_order"
    )
    existing = {
        r["source_key"]
        for r in sb.rest_all(
            "product_image_presets", "select=source_key&source_key=not.is.null&order=source_key"
        )
    }
    top = sb.request(
        "GET", "/rest/v1/product_image_presets?select=display_order&order=display_order.desc&limit=1"
    )
    next_order = (top[0]["display_order"] if top else 0) + 1
    folder_by_fold = {fold(f["name"].strip()): f for f in folders}

    # Plan
    todo, seen, skipped = [], set(), []
    by_folder = {}
    for it in items:
        stat = by_folder.setdefault(it.folder_dir, {"new": 0, "have": 0, "bad": 0})
        if not it.name:
            warnings.append(
                f"{it.rel}: ad çıkarılamadı (IMG_... gibi); {CSV_NAME}'de ad verin ya da "
                "dosyayı yeniden adlandırın (atlandı)"
            )
            stat["bad"] += 1
            continue
        if len(it.folder_dir) > 40:
            warnings.append(f"{it.folder_dir}: klasör adı 40 karakterden uzun (atlandı)")
            stat["bad"] += 1
            continue
        if it.key in existing:
            stat["have"] += 1
            continue
        if it.key in seen:
            warnings.append(f"{it.rel}: aynı klasörde aynı adlı başka görsel var ({it.key}) (atlandı)")
            stat["bad"] += 1
            continue
        seen.add(it.key)
        stat["new"] += 1
        todo.append(it)

    print(f"Kök: {root}")
    print(f"Mod: {'YÜKLEME' if args.yukle else 'KURU ÇALIŞTIRMA (hiçbir şey yazılmaz)'}"
          f"{' · pasif eklenecek' if args.pasif else ''}")
    print()
    width = max(len(k) for k in by_folder)
    closed = []
    for name, st in by_folder.items():
        folder = folder_by_fold.get(fold(name))
        if folder is None:
            tag = "YENİ  "
        elif folder["is_active"]:
            tag = "var   "
        else:
            tag = "KAPALI"
            if st["new"]:
                closed.append(folder["name"])
        print(f"  {name.ljust(width)}  [{tag}]  {st['new']:>5} yeni  {st['have']:>5} zaten yüklü"
              + (f"  {st['bad']:>4} atlandı" if st["bad"] else ""))
    print()
    for name in closed:
        warnings.append(
            f"'{name}' klasörü admin panelinde KAPALI: yüklenen görseller satıcılara "
            "klasör açılana kadar görünmez"
        )
    if warnings:
        print(f"Uyarılar ({len(warnings)}):")
        for w in warnings[:60]:
            print("  - " + w)
        if len(warnings) > 60:
            print(f"  ... ve {len(warnings) - 60} uyarı daha")
        print()

    if not todo:
        print("Yüklenecek yeni görsel yok.")
        return
    if not args.yukle:
        print(f"{len(todo)} yeni görsel yüklenecek. Yüklemek için komutun sonuna --yukle ekleyin.")
        return

    # Eksik klasörleri oluştur
    max_folder_order = max((f["display_order"] for f in folders), default=0)
    for name in by_folder:
        if fold(name) in folder_by_fold or not any(t.folder_dir == name for t in todo):
            continue
        max_folder_order += 1
        created = sb.request(
            "POST", "/rest/v1/product_image_folders",
            body={"name": name, "display_order": max_folder_order},
            headers={"Prefer": "return=representation"},
        )[0]
        folder_by_fold[fold(name)] = created
        print(f"Klasör oluşturuldu: {name}")

    for i, it in enumerate(todo):
        it.order = next_order + i

    lock = threading.Lock()
    done, failed, total_bytes = [0], [], [0]

    def work(it):
        data, digest, _ = to_webp(it.path, args.boyut, args.kalite)
        if len(data) > MAX_BYTES:
            raise RuntimeError(f"dönüştürülmüş dosya {len(data) // 1024} KB (sınır 2 MB)")
        storage_path = f"library/{slug(it.folder_dir)}/{slug(it.name)}-{digest}.webp"
        url = sb.upload(storage_path, data)
        sb.request(
            "POST", "/rest/v1/product_image_presets?on_conflict=source_key",
            body={
                "name": it.name,
                "description": it.keywords,
                "image_url": url,
                "is_active": not args.pasif,
                "display_order": it.order,
                "folder_id": folder_by_fold[fold(it.folder_dir)]["id"],
                "source_key": it.key,
            },
            headers={"Prefer": "resolution=ignore-duplicates,return=minimal"},
        )
        return len(data)

    print(f"{len(todo)} görsel yükleniyor ({WORKERS} paralel)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {pool.submit(work, it): it for it in todo}
        for fut in concurrent.futures.as_completed(futures):
            it = futures[fut]
            with lock:
                try:
                    total_bytes[0] += fut.result()
                    done[0] += 1
                except Exception as e:  # noqa: BLE001 — her hatayı raporla, devam et
                    failed.append((it.rel, str(e)))
                n = done[0] + len(failed)
                if n % 25 == 0 or n == len(todo):
                    print(f"  {n}/{len(todo)}")

    print()
    avg = total_bytes[0] / done[0] / 1024 if done[0] else 0
    print(f"Tamamlandı: {done[0]} görsel yüklendi (ortalama {avg:.0f} KB)"
          + (", PASİF eklendi — admin panelinde kontrol edip yayına alın" if args.pasif else ""))
    if failed:
        print(f"{len(failed)} görsel yüklenemedi (aynı komutu tekrar çalıştırınca yalnız bunlar denenir):")
        for rel, err in failed[:50]:
            print(f"  - {rel}: {err}")
        sys.exit(1)


if __name__ == "__main__":
    main()
