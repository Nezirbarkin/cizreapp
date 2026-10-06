#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Urun Gorsel Kutuphanesi icin 2000 urun gorselini yapay zekayla uretir (beyaz zemin).

Kaynak listeler (4 x 500 urun; elle duzenlenebilir):
    scripts/product_image_library/hirdavat.txt   -> klasor "Hırdavat"
    scripts/product_image_library/market.txt     -> klasor "Market"     (markali)
    scripts/product_image_library/kozmetik.txt   -> klasor "Kozmetik"   (markali)
    scripts/product_image_library/zuccaciye.txt  -> klasor "Züccaciye"
  Satir bicimi:  Ad | arama kelimeleri | gorsel tarifi (Ingilizce)

Akis:
    1) python scripts/generate_product_image_library.py
         KURU: plan + tahmini maliyet; cikti klasorune kelimeler.csv yazar. API cagrisi YOK.
    2) $env:OPENAI_API_KEY="sk-..."        (ya da $env:GEMINI_API_KEY="...")
       python scripts/generate_product_image_library.py --uret --saglayici openai --deneme 4
         Her klasorden 1 gorsel uretir: kaliteyi ve faturayi kontrol edin.
    3) python scripts/generate_product_image_library.py --uret --saglayici openai
         Kalanlarin hepsini uretir. Yarida kalirsa ayni komut yalniz eksikleri uretir.
    4) python scripts/upload_product_image_library.py build/urun_gorsel_kutuphanesi --yukle --pasif
         Kutuphaneye yukler (800 px WebP); admin panelinde kontrol edip yayina alin.

Secenekler:
    --uret              API'yi gercekten cagir (verilmezse kuru calisma).
    --saglayici         openai (varsayilan) | gemini | cloudflare
    --model             Varsayilan: openai -> gpt-image-1-mini, gemini -> gemini-3.1-flash-image,
                        cloudflare -> @cf/black-forest-labs/flux-2-klein-4b
                        (ya da @cf/black-forest-labs/flux-1-schnell)
    --cf-hesap ID       Cloudflare hesap kimligi (ya da CLOUDFLARE_ACCOUNT_ID)
    --kalite            openai icin low | medium (varsayilan) | high
    --klasor            Yalniz bir klasor: Hırdavat | Market | Kozmetik | Züccaciye
    --deneme N          Yalniz N gorsel uret (klasorler arasinda sirayla).
    --paralel N         Ayni anda istek (varsayilan 3).
    --cikti DIR         Cikti klasoru (varsayilan build/urun_gorsel_kutuphanesi; git'e girmez).

Beyaz zemin iki katmanda saglanir: (1) istem saf beyaz zemin ister; (2) uretilen gorselde
koselerden baslayan tasma dolgusuyla zemin #FFFFFF'e cekilir (urunun yumusak golgesi kalir).
Kosesi beyaz olmayan gorsel bir kez yeniden uretilir; yine olmazsa zemin_kontrol.txt'ye yazilir.

Markali urunlerde (Market, Kozmetik) istem ambalajin YAZISIZ ve LOGOSUZ olmasini ister:
yapay zeka gercek marka ambalajini dogru ciziemez (bozuk logo/yazi) ve marka taklidi olur.
Marka adi gorselin ADINDA ve arama kelimelerinde durur; satici "Ülker" yazinca bulur.

Fiyatlar yaklasiktir (Ekim 2026): gpt-image-1-mini 1024px low ~0,005 $, medium ~0,011 $,
high ~0,036 $; gemini-3.1-flash-image 1K ~0,067 $. Kesin tutar saglayicinin faturasindadir.

Cloudflare Workers AI: her hesaba gunde 10.000 "neuron" UCRETSIZ. flux-2-klein-4b 768 px ~59,
flux-1-schnell 1024 px (4 adim) ~58 neuron -> gunde ~170 gorsel. Kota dolunca betik durur;
ertesi gun (00:00 UTC'den sonra) ayni komut kaldigi yerden devam eder. Token:
CLOUDFLARE_API_TOKEN ortam degiskeni ya da %USERPROFILE%\\.cloudflare_ai_token dosyasi
(proje DISINDA; git'e ve uygulamaya girmez). Token yalniz "Workers AI" yetkisi tasimalidir.
"""

import argparse
import base64
import binascii
import concurrent.futures
import csv
import io
import json
import math
import os
import random
import sys
import threading
import time
import urllib.error
import urllib.request

from PIL import Image, ImageChops, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIST_DIR = os.path.join(ROOT, "scripts", "product_image_library")
DEFAULT_OUT = os.path.join(ROOT, "build", "urun_gorsel_kutuphanesi")

# kaynak dosya -> (klasor adi, markali mi)
SOURCES = [
    ("hirdavat.txt", "Hırdavat", False),
    ("market.txt", "Market", True),
    ("kozmetik.txt", "Kozmetik", True),
    ("zuccaciye.txt", "Züccaciye", False),
]

DEFAULT_MODEL = {
    "openai": "gpt-image-1-mini",
    "gemini": "gemini-3.1-flash-image",
    "cloudflare": "@cf/black-forest-labs/flux-2-klein-4b",
}
PRICE = {  # gorsel basina yaklasik $ (Ekim 2026)
    ("openai", "low"): 0.005,
    ("openai", "medium"): 0.011,
    ("openai", "high"): 0.036,
    ("gemini", None): 0.067,
    ("cloudflare", None): 0.00065,  # ucretsiz kota disinda; kota icinde 0 $
}
CF_FREE_PER_DAY = 170  # 10.000 neuron / ~59 neuron

PROMPT = (
    "Professional e-commerce product photograph of {subject}. Single product, centered, "
    "filling about 70% of the frame, on a pure solid white background (#FFFFFF): no gradient, "
    "no props, no table surface, no reflections, only a very soft natural shadow under the "
    "product. Soft even studio lighting, photorealistic, sharp focus, square 1:1 composition."
)
# Markalı ürünler: gerçek ambalaj taklit edilmez. "plain/unbranded" denince model bembeyaz
# boş kutu çiziyor, "colorful abstract" denince hepsi aynı gökkuşağı deseni oluyor; denenen
# en dengeli istem bu (2026-10-06, flux-2-klein-4b). Kozmetikte "içeriğin resmi" istenmez:
# şampuana kuruyemiş çizdi.
_NO_TEXT = (" It contains absolutely no readable text, no letters, no numbers, no barcodes "
            "and no logos.")
BRANDED = (
    " The packaging has a realistic, simple retail design: one or two main colors that suit "
    "this kind of product, a small picture of the contents, and plenty of clean space." + _NO_TEXT
)
BRANDED_COSMETIC = (
    " The packaging has a realistic, elegant retail design: one or two main colors that suit "
    "this kind of product and plenty of clean space." + _NO_TEXT
)
GENERIC = " No text, no logos, no watermark."

try:
    sys.stdout.reconfigure(errors="replace")
    sys.stderr.reconfigure(errors="replace")
except AttributeError:
    pass


# ---------------------------------------------------------------------------
# Liste
# ---------------------------------------------------------------------------


class Product:
    def __init__(self, folder, name, keywords, subject, branded):
        self.folder = folder
        self.name = name
        self.keywords = keywords
        self.subject = subject
        self.branded = branded
        self.file = name + ".jpg"
        self.rel = folder + "/" + self.file

    @property
    def prompt(self):
        if not self.branded:
            tail = GENERIC
        elif self.folder == "Kozmetik":
            tail = BRANDED_COSMETIC
        else:
            tail = BRANDED
        return PROMPT.format(subject=self.subject) + tail


def load_products():
    out = []
    for fname, folder, branded in SOURCES:
        path = os.path.join(LIST_DIR, fname)
        for n, line in enumerate(open(path, encoding="utf-8"), start=1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) != 3 or not all(parts):
                sys.exit(f"{fname}:{n}: 'Ad | kelimeler | tarif' bekleniyordu: {line}")
            out.append(Product(folder, parts[0], parts[1], parts[2], branded))
    return out


def write_csv(out_dir, products):
    """Yukleme betiginin okudugu kelimeler.csv (dosya;ad;kelimeler)."""
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "kelimeler.csv")
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["dosya", "ad", "kelimeler"])
        for p in products:
            w.writerow([p.rel, p.name, p.keywords])
    return path


# ---------------------------------------------------------------------------
# Beyaz zemin
# ---------------------------------------------------------------------------


_MARK = (255, 0, 255)  # taşma dolgusu işaret rengi (beyazdan uzak)


def _near_white(px, limit=226):
    return all(c >= limit for c in px[:3])


def whiten_background(im):
    """Koselerden ve kenar ortalarindan baslayan, beyaza yakin bitisik zemini #FFFFFF yapar.
    Doner: (gorsel, zemin_tamam). Urunun icindeki beyazlara (bitisik degilse) dokunmaz."""
    im = im.convert("RGB")
    w, h = im.size
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
             (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]
    white_seeds = [s for s in seeds if _near_white(im.getpixel(s))]
    if len(white_seeds) < 6:  # model zemini beyaz yapmamis
        return im, False
    # Dogrudan beyazla doldurulamaz: Pillow floodfill, dolgu rengi baslangic pikseline
    # thresh kadar yakinsa "zaten dolu" deyip hicbir sey yapmaz (zemin 248,248,246 iken
    # tam olarak bu olur). Once beyazdan uzak bir isaret rengiyle doldurup degisen
    # pikselleri beyaza cekiyoruz.
    work = im.copy()
    for s in white_seeds:
        if work.getpixel(s) != _MARK:
            ImageDraw.floodfill(work, s, _MARK, thresh=30)
    changed = ImageChops.difference(work, im).convert("L").point(lambda v: 255 if v else 0)
    im.paste((255, 255, 255), (0, 0), changed)
    # Kenar seridinin neredeyse tamami beyaz olmali
    border = [im.getpixel((x, y)) for x in range(0, w, 8) for y in (0, h - 1)]
    border += [im.getpixel((x, y)) for y in range(0, h, 8) for x in (0, w - 1)]
    ok = sum(1 for px in border if px == (255, 255, 255)) / len(border) >= 0.97
    return im, ok


# ---------------------------------------------------------------------------
# Saglayicilar
# ---------------------------------------------------------------------------


class ApiError(Exception):
    def __init__(self, code, detail):
        super().__init__(f"HTTP {code}: {detail}")
        self.code = code
        self.detail = detail


class QuotaExhausted(Exception):
    """Günlük ücretsiz kota bitti: yeniden denemek anlamsız, üretim durur."""


def _post(url, data, headers):
    req = urllib.request.Request(url, data=data, method="POST", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise ApiError(e.code, e.read().decode("utf-8", "replace")[:400]) from None


def _post_json(url, body, headers):
    data = json.dumps(body).encode("utf-8")
    return _post(url, data, {"Content-Type": "application/json", **headers})


def _post_multipart(url, fields, headers):
    boundary = "----cizreapp" + "".join(random.choices("0123456789abcdef", k=24))
    parts = []
    for name, value in fields.items():
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n"
            f"{value}\r\n".encode("utf-8")
        )
    parts.append(f"--{boundary}--\r\n".encode("utf-8"))
    return _post(url, b"".join(parts),
                 {"Content-Type": f"multipart/form-data; boundary={boundary}", **headers})


def _find_image(obj):
    """Yanit JSON'unda base64 gorseli bulur (b64_json / inlineData.data / output_image ...)."""
    stack = [obj]
    while stack:
        cur = stack.pop()
        if isinstance(cur, dict):
            stack.extend(cur.values())
        elif isinstance(cur, list):
            stack.extend(cur)
        elif isinstance(cur, str) and len(cur) > 2000:
            try:
                raw = base64.b64decode(cur, validate=True)
                Image.open(io.BytesIO(raw)).verify()
                return raw
            except (binascii.Error, ValueError, OSError, SyntaxError):
                continue
    return None


class OpenAI:
    def __init__(self, model, quality):
        self.key = os.environ.get("OPENAI_API_KEY")
        if not self.key:
            sys.exit('OPENAI_API_KEY yok. PowerShell: $env:OPENAI_API_KEY="sk-..."')
        self.model, self.quality = model, quality

    def generate(self, prompt):
        res = _post_json(
            "https://api.openai.com/v1/images/generations",
            {"model": self.model, "prompt": prompt, "size": "1024x1024",
             "quality": self.quality, "background": "opaque", "n": 1},
            {"Authorization": "Bearer " + self.key},
        )
        raw = _find_image(res)
        if raw is None:
            raise RuntimeError("yanıtta görsel yok: " + json.dumps(res)[:300])
        return raw


class Gemini:
    BASE = "https://generativelanguage.googleapis.com/v1beta"

    def __init__(self, model):
        self.key = os.environ.get("GEMINI_API_KEY")
        if not self.key:
            sys.exit('GEMINI_API_KEY yok. PowerShell: $env:GEMINI_API_KEY="..."')
        self.model = model
        self.mode = None  # ilk basarili uc nokta hatirlanir

    def _generate_content(self, prompt):
        return _post_json(
            f"{self.BASE}/models/{self.model}:generateContent",
            {"contents": [{"parts": [{"text": prompt}]}],
             "generationConfig": {"responseModalities": ["IMAGE"],
                                  "imageConfig": {"aspectRatio": "1:1"}}},
            {"x-goog-api-key": self.key},
        )

    def _interactions(self, prompt):
        return _post_json(
            f"{self.BASE}/interactions",
            {"model": self.model, "input": [{"type": "text", "text": prompt}],
             "response_format": {"type": "image", "mime_type": "image/jpeg",
                                 "aspect_ratio": "1:1", "image_size": "1K"}},
            {"x-goog-api-key": self.key},
        )

    def generate(self, prompt):
        """Google görsel API'si 2026'da generateContent'ten interactions'a geçti; hangisinin
        çalıştığı ilk başarılı çağrıda öğrenilir ve sonra hep o kullanılır."""
        order = [self.mode] if self.mode else ["generateContent", "interactions"]
        last = None
        for mode in order:
            fn = self._generate_content if mode == "generateContent" else self._interactions
            try:
                raw = _find_image(fn(prompt))
                if raw is None:
                    raise RuntimeError(f"{mode}: yanıtta görsel yok")
            except ApiError as e:
                if self.mode or e.code not in (400, 404):
                    raise
                last = e
                continue
            except RuntimeError as e:
                if self.mode:
                    raise
                last = e
                continue
            self.mode = mode
            return raw
        raise last


class Cloudflare:
    """Workers AI. FLUX.2 modelleri multipart/form-data ister (genişlik/yükseklik
    verilebilir); flux-1-schnell JSON ister ve 1024 px üretir."""

    TOKEN_FILE = os.path.join(os.path.expanduser("~"), ".cloudflare_ai_token")

    def __init__(self, model, account):
        self.account = account or os.environ.get("CLOUDFLARE_ACCOUNT_ID")
        if not self.account:
            sys.exit("Cloudflare hesap kimliği yok: --cf-hesap <ID> verin")
        token = os.environ.get("CLOUDFLARE_API_TOKEN")
        if not token and os.path.exists(self.TOKEN_FILE):
            token = open(self.TOKEN_FILE, encoding="utf-8-sig").read().strip()
        if not token:
            sys.exit(f"Cloudflare token yok: {self.TOKEN_FILE} dosyasına yazın "
                     "ya da CLOUDFLARE_API_TOKEN verin")
        self.headers = {"Authorization": "Bearer " + token}
        self.model = model
        self.url = (f"https://api.cloudflare.com/client/v4/accounts/{self.account}"
                    f"/ai/run/{model}")

    def generate(self, prompt):
        try:
            if "flux-2" in self.model:
                res = _post_multipart(self.url, {"prompt": prompt, "width": 768, "height": 768},
                                      self.headers)
            else:
                res = _post_json(self.url, {"prompt": prompt, "steps": 4}, self.headers)
        except ApiError as e:
            text = (e.detail or "").lower()
            # 4006: günlük ücretsiz neuron kotası bitti
            if "4006" in text or ("neuron" in text and ("daily" in text or "allocation" in text)):
                raise QuotaExhausted(e.detail) from None
            raise
        raw = _find_image(res)
        if raw is None:
            raise RuntimeError("yanıtta görsel yok: " + json.dumps(res)[:300])
        return raw


# ---------------------------------------------------------------------------
# Uretim
# ---------------------------------------------------------------------------


def produce(provider, product, out_dir):
    """Uretir, zemini beyazlatir, kaydeder. Doner: zemin_tamam."""
    attempt, ok = 0, False
    while True:
        attempt += 1
        delay, flagged = 5, 0
        for retry in range(6):  # 429/5xx icin bekleyip yeniden dene
            try:
                raw = provider.generate(product.prompt)
                break
            except ApiError as e:
                # Cloudflare içerik filtresi zararsız ürün görselini de ara sıra
                # "flagged" (3030) diye reddeder; çıktı her seferinde farklı olduğu
                # için birkaç kez yeniden denemek çoğu zaman yeter.
                if e.code == 400 and "flagged" in (e.detail or "").lower() and flagged < 2:
                    flagged += 1
                    continue
                # 408: Cloudflare yoğunlukta "Request timeout" (3046) döner; geçicidir.
                if e.code in (408, 429, 500, 502, 503, 504) and retry < 5:
                    time.sleep(delay + random.random() * 2)
                    delay = min(delay * 2, 90)
                    continue
                raise
        im, ok = whiten_background(Image.open(io.BytesIO(raw)))
        if ok or attempt >= 2:
            break
    folder = os.path.join(out_dir, product.folder)
    os.makedirs(folder, exist_ok=True)
    tmp = os.path.join(folder, product.file + ".tmp")
    im.save(tmp, "JPEG", quality=95, subsampling=0, optimize=True)
    os.replace(tmp, os.path.join(folder, product.file))  # yarim dosya kalmasin
    return ok


def round_robin(items):
    """Klasorler arasinda sirayla: deneme N ile her klasorden ornek gelsin."""
    by = {}
    for it in items:
        by.setdefault(it.folder, []).append(it)
    out, i = [], 0
    while any(i < len(v) for v in by.values()):
        for v in by.values():
            if i < len(v):
                out.append(v[i])
        i += 1
    return out


def main():
    ap = argparse.ArgumentParser(description="Ürün görsel kütüphanesi için görsel üretimi")
    ap.add_argument("--uret", action="store_true", help="API'yi gerçekten çağır")
    ap.add_argument("--saglayici", choices=["openai", "gemini", "cloudflare"], default="openai")
    ap.add_argument("--model")
    ap.add_argument("--cf-hesap", help="Cloudflare hesap kimliği")
    ap.add_argument("--kalite", choices=["low", "medium", "high"], default="medium")
    ap.add_argument("--klasor", choices=[s[1] for s in SOURCES])
    ap.add_argument("--deneme", type=int)
    ap.add_argument("--paralel", type=int, default=3)
    ap.add_argument("--cikti", default=DEFAULT_OUT)
    args = ap.parse_args()

    products = load_products()
    out_dir = os.path.abspath(args.cikti)
    csv_path = write_csv(out_dir, products)

    selected = [p for p in products if not args.klasor or p.folder == args.klasor]
    missing = [p for p in selected
               if not os.path.exists(os.path.join(out_dir, p.folder, p.file))]
    todo = round_robin(missing)
    if args.deneme:
        todo = todo[: args.deneme]

    model = args.model or DEFAULT_MODEL[args.saglayici]
    unit = PRICE.get((args.saglayici, args.kalite if args.saglayici == "openai" else None))

    print(f"Çıktı: {out_dir}")
    print(f"kelimeler.csv yazıldı ({len(products)} satır): {csv_path}")
    print()
    for _, folder, _ in SOURCES:
        if args.klasor and args.klasor != folder:
            continue
        total = sum(1 for p in products if p.folder == folder)
        have = total - sum(1 for p in missing if p.folder == folder)
        print(f"  {folder:<10} {have:>4}/{total} hazır")
    print()
    if args.saglayici == "cloudflare":
        days = math.ceil(len(todo) / CF_FREE_PER_DAY)
        est = (f" · ücretsiz kotayla ~{CF_FREE_PER_DAY}/gün → ~{days} gün"
               f" (ücretli planda ~{len(todo) * unit:.2f} $)")
    else:
        est = f" · tahmini maliyet ~{len(todo) * unit:.2f} $" if unit else ""
    print(f"Üretilecek: {len(todo)} görsel · {args.saglayici} / {model}"
          + (f" / {args.kalite}" if args.saglayici == "openai" else "") + est)

    if not todo:
        print("Üretilecek görsel yok.")
        return
    if not args.uret:
        print("KURU ÇALIŞTIRMA: hiçbir API çağrılmadı. Üretmek için --uret ekleyin "
              "(önce --deneme 4 önerilir).")
        return

    if args.saglayici == "openai":
        provider = OpenAI(model, args.kalite)
    elif args.saglayici == "gemini":
        provider = Gemini(model)
    else:
        provider = Cloudflare(model, args.cf_hesap)
    lock = threading.Lock()
    done, failed, not_white = [0], [], []
    quota = []
    log_fail = os.path.join(out_dir, "uretim_hatalari.txt")
    log_white = os.path.join(out_dir, "zemin_kontrol.txt")
    started = time.time()

    stop = threading.Event()

    def work(p):
        # Kota dolduysa sıradakiler API'ye hiç gitmesin (iptal gelene kadar geçen
        # sürede işçi iş parçacıkları yeni görevlere başlamış olabilir).
        if stop.is_set():
            raise QuotaExhausted("durduruldu")
        try:
            return produce(provider, p, out_dir)
        except QuotaExhausted:
            stop.set()
            raise

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.paralel)) as pool:
        futures = {pool.submit(work, p): p for p in todo}
        for fut in concurrent.futures.as_completed(futures):
            p = futures[fut]
            if fut.cancelled():
                continue
            with lock:
                try:
                    if not fut.result():
                        not_white.append(p.rel)
                    done[0] += 1
                except SystemExit:
                    raise
                except QuotaExhausted as e:
                    if not quota:
                        quota.append(str(e))
                        for other in futures:  # bekleyenleri iptal et
                            other.cancel()
                    continue
                except Exception as e:  # noqa: BLE001 — raporla, devam et
                    failed.append((p.rel, str(e)))
                n = done[0] + len(failed)
                if n % 10 == 0 or n == len(todo):
                    mins = (time.time() - started) / 60
                    print(f"  {n}/{len(todo)}  ({mins:.1f} dk, {len(failed)} hata)")

    if failed:
        with open(log_fail, "w", encoding="utf-8") as f:
            f.writelines(f"{rel}\t{err}\n" for rel, err in failed)
    if not_white:
        with open(log_white, "w", encoding="utf-8") as f:
            f.writelines(rel + "\n" for rel in not_white)

    print()
    cost = "" if args.saglayici == "cloudflare" or not unit else f" · ~{done[0] * unit:.2f} $"
    print(f"Tamamlandı: {done[0]} görsel üretildi" + cost)
    if quota:
        left = len(todo) - done[0] - len(failed)
        print(f"GÜNLÜK ÜCRETSİZ KOTA DOLDU: {left} görsel kaldı. Yarın (Türkiye saatiyle "
              "03:00'ten sonra) aynı komutu çalıştırın; kaldığı yerden devam eder.")
    if not_white:
        print(f"{len(not_white)} görselin zemini tam beyaz olmadı (2 deneme): {log_white}")
        print("  Bu dosyaları silip komutu tekrar çalıştırırsanız yeniden üretilir.")
    if failed:
        print(f"{len(failed)} görsel üretilemedi: {log_fail}")
        print("  Aynı komutu tekrar çalıştırınca yalnız eksikler denenir.")
        sys.exit(1)
    print("Sonraki adım: python scripts/upload_product_image_library.py "
          f"\"{out_dir}\" --yukle --pasif")


if __name__ == "__main__":
    main()
