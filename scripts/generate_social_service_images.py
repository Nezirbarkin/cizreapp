#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Dijital urunler icin kutuphane gorselleri cizer.

Iki tasarim:
  * Sosyal medya hizmeti (Instagram, TikTok, X, YouTube, Facebook, Telegram, Twitch,
    Spotify, Threads: takipci, begeni, yorum, izlenme ...): platform renginde zemin,
    ortada beyaz daire icinde hizmet simgesi, altta Turkce etiket, gerekirse TÜRK /
    YABANCI rozeti.
  * Hesap / abonelik / lisans (ChatGPT Plus, Gemini Pro 18 Aylık, Canva Pro ...): marka
    renginde kart, buyuk urun adi, plan ve sure rozeti.
Resmi logolar KULLANILMAZ (tescilli marka): ad yaziyla, renkler cagristiracak kadar.

Cikti upload_product_image_library.py bicimindedir:

    build/dijital_gorseller/
      Dijital/Instagram Türk Takipçi.png
      kelimeler.csv
      ornekler.png        (tum setin kucuk onizlemesi)

Kullanim:
    python scripts/generate_social_service_images.py
    python scripts/upload_product_image_library.py build/dijital_gorseller --yukle
"""

import csv
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "build", "dijital_gorseller")
FOLDER = "Dijital"
S = 2000  # cizim boyutu; kayitta 1000 px'e kucultulur (kenar yumusatma)
FINAL = 1000
FONT_DIR = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")
FONT_BLACK = os.path.join(FONT_DIR, "seguibl.ttf")
FONT_BOLD = os.path.join(FONT_DIR, "segoeuib.ttf")

IG_STOPS = [(0.0, (254, 218, 117)), (0.25, (250, 126, 30)), (0.5, (214, 41, 118)),
            (0.75, (150, 47, 191)), (1.0, (79, 91, 213))]
TT_BG = (14, 14, 18)
TT_CYAN = (37, 244, 238)
TT_RED = (254, 44, 85)
TR_RED = (227, 10, 23)
FOREIGN_BLUE = (29, 78, 216)

# bg: ("gradient", duraklar) | ("glow", zemin, sol ust parilti, sag alt parilti)
# icon: "gradient" (zemin degradesi) | "glitch" (TikTok) | (r, g, b)
PLATFORMS = {
    "instagram": {"label": "Instagram", "words": "instagram, insta, ig, sosyal medya",
                  "bg": ("gradient", IG_STOPS), "icon": "gradient"},
    "tiktok": {"label": "TikTok", "words": "tiktok, tik tok, sosyal medya",
               "bg": ("glow", TT_BG, TT_CYAN, TT_RED), "icon": "glitch"},
    "x": {"label": "X (Twitter)", "words": "x, twitter, tweet, sosyal medya",
          "bg": ("glow", (8, 8, 10), (120, 120, 130), (60, 60, 70)), "icon": (15, 20, 25)},
    "youtube": {"label": "YouTube", "words": "youtube, yt, video, sosyal medya",
                "bg": ("gradient", [(0, (255, 40, 60)), (1, (150, 0, 18))]), "icon": (230, 0, 35)},
    "facebook": {"label": "Facebook", "words": "facebook, fb, meta, sosyal medya",
                 "bg": ("gradient", [(0, (60, 140, 255)), (1, (10, 70, 170))]), "icon": (24, 119, 242)},
    "telegram": {"label": "Telegram", "words": "telegram, kanal, grup, sosyal medya",
                 "bg": ("gradient", [(0, (60, 190, 245)), (1, (20, 110, 185))]), "icon": (34, 158, 217)},
    "twitch": {"label": "Twitch", "words": "twitch, yayın, yayıncı, sosyal medya",
               "bg": ("gradient", [(0, (160, 100, 255)), (1, (75, 20, 170))]), "icon": (145, 70, 255)},
    "spotify": {"label": "Spotify", "words": "spotify, müzik, şarkı, sosyal medya",
                "bg": ("glow", (14, 14, 14), (29, 185, 84), (10, 90, 45)), "icon": (24, 160, 72)},
    "threads": {"label": "Threads", "words": "threads, meta, sosyal medya",
                "bg": ("glow", (10, 10, 12), (90, 90, 100), (50, 50, 60)), "icon": (15, 15, 18)},
}

# (platform, ad, simge, etiket, rozet, ek kelimeler)
ITEMS = [
    ("instagram", "Instagram Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("instagram", "Instagram Türk Takipçi", "follow", "TAKİPÇİ", "TÜRK", "takipçi, türk, yerli, follower"),
    ("instagram", "Instagram Yabancı Takipçi", "follow", "TAKİPÇİ", "YABANCI", "takipçi, yabancı, global, follower"),
    ("instagram", "Instagram Türk Kadın Takipçi", "follow", "TAKİPÇİ", "TÜRK KADIN", "takipçi, türk, kadın, bayan, follower"),
    ("instagram", "Instagram Beğeni", "heart", "BEĞENİ", None, "beğeni, like, kalp"),
    ("instagram", "Instagram Türk Beğeni", "heart", "BEĞENİ", "TÜRK", "beğeni, türk, yerli, like"),
    ("instagram", "Instagram Yabancı Beğeni", "heart", "BEĞENİ", "YABANCI", "beğeni, yabancı, global, like"),
    ("instagram", "Instagram Yorum", "comment", "YORUM", None, "yorum, comment"),
    ("instagram", "Instagram Türk Yorum", "comment", "YORUM", "TÜRK", "yorum, türk, comment"),
    ("instagram", "Instagram Kaydetme", "bookmark", "KAYDETME", None, "kaydet, kaydetme, save"),
    ("instagram", "Instagram İzlenme", "eye", "İZLENME", None, "izlenme, video, view"),
    ("instagram", "Instagram Reels İzlenme", "reels", "REELS İZLENME", None, "reels, izlenme, video, view"),
    ("instagram", "Instagram Hikaye İzlenme", "story", "HİKAYE İZLENME", None, "hikaye, story, izlenme"),
    ("instagram", "Instagram Görüntülenme", "chart", "GÖRÜNTÜLENME", None, "görüntülenme, gösterim, erişim, impression"),
    ("instagram", "Instagram Paylaşım", "share", "PAYLAŞIM", None, "paylaşım, gönder, share"),
    ("instagram", "Instagram Canlı Yayın İzleyici", "live", "CANLI YAYIN", None, "canlı yayın, izleyici, live"),
    ("tiktok", "TikTok Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("tiktok", "TikTok Türk Takipçi", "follow", "TAKİPÇİ", "TÜRK", "takipçi, türk, yerli, follower"),
    ("tiktok", "TikTok Yabancı Takipçi", "follow", "TAKİPÇİ", "YABANCI", "takipçi, yabancı, global, follower"),
    ("tiktok", "TikTok Beğeni", "heart", "BEĞENİ", None, "beğeni, like, kalp"),
    ("tiktok", "TikTok Türk Beğeni", "heart", "BEĞENİ", "TÜRK", "beğeni, türk, yerli, like"),
    ("tiktok", "TikTok Yabancı Beğeni", "heart", "BEĞENİ", "YABANCI", "beğeni, yabancı, global, like"),
    ("tiktok", "TikTok Yorum", "comment", "YORUM", None, "yorum, comment"),
    ("tiktok", "TikTok Kaydetme", "bookmark", "KAYDETME", None, "kaydet, favori, save"),
    ("tiktok", "TikTok İzlenme", "play", "İZLENME", None, "izlenme, video, view"),
    ("tiktok", "TikTok Paylaşım", "share", "PAYLAŞIM", None, "paylaşım, share"),
    ("tiktok", "TikTok Canlı Yayın İzleyici", "live", "CANLI YAYIN", None, "canlı yayın, izleyici, live"),
    ("x", "X (Twitter) Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("x", "X (Twitter) Türk Takipçi", "follow", "TAKİPÇİ", "TÜRK", "takipçi, türk, yerli, follower"),
    ("x", "X (Twitter) Yabancı Takipçi", "follow", "TAKİPÇİ", "YABANCI", "takipçi, yabancı, global, follower"),
    ("x", "X (Twitter) Beğeni", "heart", "BEĞENİ", None, "beğeni, like, fav"),
    ("x", "X (Twitter) Türk Beğeni", "heart", "BEĞENİ", "TÜRK", "beğeni, türk, yerli, like"),
    ("x", "X (Twitter) Retweet", "repost", "RETWEET", None, "retweet, rt, repost, yeniden paylaş"),
    ("x", "X (Twitter) Yorum", "comment", "YORUM", None, "yorum, yanıt, reply"),
    ("x", "X (Twitter) Görüntülenme", "chart", "GÖRÜNTÜLENME", None, "görüntülenme, gösterim, izlenme, view"),
    ("x", "X (Twitter) Yer İşareti", "bookmark", "YER İŞARETİ", None, "yer işareti, kaydet, bookmark"),
    ("youtube", "YouTube Abone", "follow", "ABONE", None, "abone, subscriber, kanal"),
    ("youtube", "YouTube Türk Abone", "follow", "ABONE", "TÜRK", "abone, türk, yerli, subscriber"),
    ("youtube", "YouTube İzlenme", "play", "İZLENME", None, "izlenme, video, view"),
    ("youtube", "YouTube Beğeni", "thumb", "BEĞENİ", None, "beğeni, like"),
    ("youtube", "YouTube Yorum", "comment", "YORUM", None, "yorum, comment"),
    ("youtube", "YouTube İzlenme Saati", "clock", "İZLENME SAATİ", None, "izlenme saati, izlenme süresi, watch time, para kazanma"),
    ("youtube", "YouTube Shorts İzlenme", "reels", "SHORTS İZLENME", None, "shorts, izlenme, kısa video"),
    ("facebook", "Facebook Sayfa Beğeni", "thumb", "SAYFA BEĞENİ", None, "sayfa beğeni, like, sayfa"),
    ("facebook", "Facebook Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("facebook", "Facebook Video İzlenme", "play", "VİDEO İZLENME", None, "video, izlenme, view"),
    ("telegram", "Telegram Kanal Üye", "group", "KANAL ÜYE", None, "üye, kanal, grup, member"),
    ("telegram", "Telegram Gönderi Görüntülenme", "eye", "GÖRÜNTÜLENME", None, "görüntülenme, gönderi, view"),
    ("twitch", "Twitch Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("twitch", "Twitch Canlı İzleyici", "live", "CANLI İZLEYİCİ", None, "canlı, izleyici, viewer"),
    ("spotify", "Spotify Dinlenme", "note", "DİNLENME", None, "dinlenme, play, stream, şarkı"),
    ("spotify", "Spotify Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower, sanatçı"),
    ("threads", "Threads Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("threads", "Threads Beğeni", "heart", "BEĞENİ", None, "beğeni, like"),
]

AI = "YAPAY ZEKÂ HESABI"
SUB = "PREMIUM ÜYELİK"
LIC = "DİJİTAL LİSANS"
_CHATGPT = [(0, (16, 163, 127)), (1, (4, 70, 54))]
_GEMINI = [(0, (66, 133, 244)), (0.55, (155, 114, 203)), (1, (217, 101, 112))]
_DARK = [(0, (52, 52, 62)), (1, (6, 6, 10))]

# (ad, ust satir, plan, sure rozeti, etiket, simge, renk duraklari, kelimeler)
ACCOUNTS = [
    ("ChatGPT Plus 1 Aylık", "ChatGPT", "Plus", "1 AYLIK", AI, "sparkle", _CHATGPT, "chatgpt, openai, gpt, plus"),
    ("ChatGPT Plus 3 Aylık", "ChatGPT", "Plus", "3 AYLIK", AI, "sparkle", _CHATGPT, "chatgpt, openai, gpt, plus"),
    ("ChatGPT Plus 12 Aylık", "ChatGPT", "Plus", "12 AYLIK", AI, "sparkle", _CHATGPT, "chatgpt, openai, gpt, plus, yıllık"),
    ("ChatGPT Pro 1 Aylık", "ChatGPT", "Pro", "1 AYLIK", AI, "sparkle", _DARK, "chatgpt, openai, gpt, pro"),
    ("Gemini Pro 1 Aylık", "Gemini", "Pro", "1 AYLIK", AI, "sparkle", _GEMINI, "gemini, google, google one, ai pro"),
    ("Gemini Pro 12 Aylık", "Gemini", "Pro", "12 AYLIK", AI, "sparkle", _GEMINI, "gemini, google, google one, ai pro, yıllık"),
    ("Gemini Pro 18 Aylık", "Gemini", "Pro", "18 AYLIK", AI, "sparkle", _GEMINI, "gemini, google, google one, ai pro, öğrenci"),
    ("Claude Pro 1 Aylık", "Claude", "Pro", "1 AYLIK", AI, "sparkle", [(0, (217, 119, 87)), (1, (120, 52, 32))], "claude, anthropic, pro"),
    ("Copilot Pro 1 Aylık", "Copilot", "Pro", "1 AYLIK", AI, "sparkle", [(0, (0, 120, 212)), (0.5, (102, 51, 204)), (1, (0, 160, 140))], "copilot, microsoft, pro"),
    ("Perplexity Pro 12 Aylık", "Perplexity", "Pro", "12 AYLIK", AI, "sparkle", [(0, (32, 128, 141)), (1, (8, 48, 54))], "perplexity, pro, arama, yıllık"),
    ("Midjourney 1 Aylık", "Midjourney", "Abonelik", "1 AYLIK", AI, "sparkle", _DARK, "midjourney, görsel, resim üretme"),
    ("Grok SuperGrok 1 Aylık", "Grok", "SuperGrok", "1 AYLIK", AI, "sparkle", _DARK, "grok, supergrok, xai, x"),
    ("Cursor Pro 1 Aylık", "Cursor", "Pro", "1 AYLIK", AI, "sparkle", _DARK, "cursor, kod, yazılım, pro"),
    ("Canva Pro 12 Aylık", "Canva", "Pro", "12 AYLIK", SUB, "crown", [(0, (0, 196, 204)), (1, (125, 42, 232))], "canva, tasarım, pro, yıllık"),
    ("CapCut Pro 1 Aylık", "CapCut", "Pro", "1 AYLIK", SUB, "crown", _DARK, "capcut, video düzenleme, pro"),
    ("Spotify Premium 1 Aylık", "Spotify", "Premium", "1 AYLIK", SUB, "note", [(0, (29, 185, 84)), (1, (8, 70, 34))], "spotify, premium, müzik"),
    ("YouTube Premium 1 Aylık", "YouTube", "Premium", "1 AYLIK", SUB, "play", [(0, (255, 40, 60)), (1, (130, 0, 16))], "youtube, premium, reklamsız"),
    ("Discord Nitro 1 Aylık", "Discord", "Nitro", "1 AYLIK", SUB, "crown", [(0, (88, 101, 242)), (1, (44, 50, 150))], "discord, nitro"),
    ("Duolingo Super 12 Aylık", "Duolingo", "Super", "12 AYLIK", SUB, "crown", [(0, (88, 204, 2)), (1, (36, 110, 0))], "duolingo, super, dil, yıllık"),
    ("Microsoft 365 Bireysel 12 Aylık", "Microsoft 365", "Bireysel", "12 AYLIK", SUB, "key", [(0, (216, 59, 1)), (1, (110, 28, 0))], "microsoft 365, office 365, word, excel, yıllık"),
    ("Windows 11 Pro Lisans", "Windows 11", "Pro", "LİSANS", LIC, "key", [(0, (0, 120, 212)), (1, (0, 50, 110))], "windows 11, windows, lisans, key, anahtar"),
    ("Office 2021 Pro Plus Lisans", "Office 2021", "Pro Plus", "LİSANS", LIC, "key", [(0, (235, 60, 0)), (1, (130, 26, 0))], "office 2021, office, word, excel, lisans, key"),
]


# ---------------------------------------------------------------------------
# Zemin
# ---------------------------------------------------------------------------


def lut(stops):
    out = []
    for i in range(256):
        x = i / 255
        for (a, ca), (b, cb) in zip(stops, stops[1:]):
            if a <= x <= b:
                t = (x - a) / (b - a) if b > a else 0
                out.append(tuple(round(ca[k] + (cb[k] - ca[k]) * t) for k in range(3)))
                break
    return out


def diagonal_gradient(stops, size=S):
    """Sol alttan sag uste capraz cok duraklı degrade."""
    g = Image.linear_gradient("L").rotate(-45, expand=True)
    w, h = g.size
    g = g.crop((w // 4, h // 4, w - w // 4, h - h // 4)).resize((size, size), Image.BICUBIC)
    table = lut(stops)
    channels = [g.point([c[k] for c in table]) for k in range(3)]
    return Image.merge("RGB", channels)


def glow_background(base, top_left, bottom_right):
    """Koyu zemin + sol ustte ve sag altta yumusak renk parlamasi."""
    bg = Image.new("RGB", (S, S), base)
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    d = ImageDraw.Draw(glow)
    d.ellipse((-500, -500, 900, 900), fill=tuple(c // 3 for c in top_left))
    d.ellipse((1100, 1100, 2500, 2500), fill=tuple(c // 3 for c in bottom_right))
    glow = glow.filter(ImageFilter.GaussianBlur(260))
    return ImageChops.add(bg, glow)


def background(spec):
    if spec[0] == "gradient":
        return diagonal_gradient(spec[1])
    return glow_background(*spec[1:])


# ---------------------------------------------------------------------------
# Simgeler (L maske, merkez cx, cy, olcek u)
# ---------------------------------------------------------------------------


def _heart_points(cx, cy, u):
    pts = []
    for i in range(240):
        t = 2 * math.pi * i / 240
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * u / 34, cy - y * u / 34 - u * 0.03))
    return pts


def icon_mask(kind, cx, cy, u):
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    if kind == "follow":
        hx = cx - u * 0.12
        d.ellipse((hx - u * 0.2, cy - u * 0.5, hx + u * 0.2, cy - u * 0.1), fill=255)
        d.pieslice((hx - u * 0.4, cy - 0.02 * u, hx + u * 0.4, cy + u * 0.78), 180, 360, fill=255)
        px, py, a, b = cx + u * 0.42, cy - u * 0.22, u * 0.17, u * 0.055
        d.rounded_rectangle((px - a, py - b, px + a, py + b), radius=b, fill=255)
        d.rounded_rectangle((px - b, py - a, px + b, py + a), radius=b, fill=255)
    elif kind == "heart":
        d.polygon(_heart_points(cx, cy, u), fill=255)
    elif kind == "comment":
        d.rounded_rectangle((cx - u * 0.48, cy - u * 0.4, cx + u * 0.48, cy + u * 0.28),
                            radius=u * 0.2, fill=255)
        d.polygon([(cx - u * 0.3, cy + u * 0.2), (cx - u * 0.36, cy + u * 0.52),
                   (cx - u * 0.04, cy + u * 0.24)], fill=255)
        for k in (-1, 0, 1):
            x = cx + k * u * 0.22
            d.ellipse((x - u * 0.065, cy - u * 0.12 - u * 0.065, x + u * 0.065, cy - u * 0.12 + u * 0.065), fill=0)
    elif kind == "bookmark":
        d.rounded_rectangle((cx - u * 0.32, cy - u * 0.5, cx + u * 0.32, cy + u * 0.1), radius=u * 0.08, fill=255)
        d.polygon([(cx - u * 0.32, cy - u * 0.05), (cx + u * 0.32, cy - u * 0.05),
                   (cx + u * 0.32, cy + u * 0.52), (cx, cy + u * 0.26),
                   (cx - u * 0.32, cy + u * 0.52)], fill=255)
    elif kind == "eye":
        a, b = u * 0.55, u * 0.36
        top = [(cx + a * math.cos(t), cy - b * math.sin(t) ** 1.25) for t in
               [math.pi * i / 80 for i in range(81)]]
        bottom = [(x, 2 * cy - y) for x, y in reversed(top)]
        d.polygon(top + bottom, fill=255)
        d.ellipse((cx - u * 0.25, cy - u * 0.25, cx + u * 0.25, cy + u * 0.25), fill=0)
        d.ellipse((cx - u * 0.14, cy - u * 0.14, cx + u * 0.14, cy + u * 0.14), fill=255)
    elif kind in ("play", "reels"):
        if kind == "reels":
            r = u * 0.5
            d.rounded_rectangle((cx - r, cy - r, cx + r, cy + r), radius=u * 0.16, fill=255)
            d.rounded_rectangle((cx - r + u * 0.09, cy - r + u * 0.09, cx + r - u * 0.09, cy + r - u * 0.09),
                                radius=u * 0.09, fill=0)
            tri = 0.24
        else:
            tri = 0.42
        d.polygon([(cx - u * tri * 0.75, cy - u * tri), (cx - u * tri * 0.75, cy + u * tri),
                   (cx + u * tri * 1.05, cy)], fill=255)
    elif kind == "story":
        r, w = u * 0.55, u * 0.09
        for k in range(10):
            start = k * 36 + 6
            d.arc((cx - r, cy - r, cx + r, cy + r), start, start + 24, fill=255, width=int(w))
        t = 0.24
        d.polygon([(cx - u * t * 0.75, cy - u * t), (cx - u * t * 0.75, cy + u * t),
                   (cx + u * t * 1.05, cy)], fill=255)
    elif kind == "chart":
        bw = u * 0.2
        for k, h in enumerate((0.45, 0.72, 1.0)):
            x = cx - u * 0.4 + k * u * 0.3
            d.rounded_rectangle((x, cy + u * 0.48 - u * h, x + bw, cy + u * 0.48), radius=bw / 2.5, fill=255)
    elif kind == "share":
        d.polygon([(cx - u * 0.52, cy - u * 0.02), (cx + u * 0.5, cy - u * 0.46),
                   (cx + u * 0.08, cy + u * 0.52), (cx - u * 0.04, cy + u * 0.06)], fill=255)
        d.polygon([(cx - u * 0.04, cy + u * 0.06), (cx + u * 0.5, cy - u * 0.46),
                   (cx - u * 0.02, cy + u * 0.02)], fill=0)
    elif kind == "live":
        d.ellipse((cx - u * 0.13, cy - u * 0.13, cx + u * 0.13, cy + u * 0.13), fill=255)
        for r in (0.32, 0.52):
            box = (cx - u * r, cy - u * r, cx + u * r, cy + u * r)
            d.arc(box, 130, 230, fill=255, width=int(u * 0.08))
            d.arc(box, -50, 50, fill=255, width=int(u * 0.08))
    elif kind == "repost":
        w, a = int(u * 0.11), u * 0.17
        d.line([(cx - u * 0.42, cy + u * 0.02), (cx - u * 0.42, cy - u * 0.26), (cx + u * 0.22, cy - u * 0.26)],
               fill=255, width=w, joint="curve")
        d.polygon([(cx + u * 0.18, cy - u * 0.26 - a), (cx + u * 0.18 + a * 1.2, cy - u * 0.26),
                   (cx + u * 0.18, cy - u * 0.26 + a)], fill=255)
        d.line([(cx + u * 0.42, cy - u * 0.02), (cx + u * 0.42, cy + u * 0.26), (cx - u * 0.22, cy + u * 0.26)],
               fill=255, width=w, joint="curve")
        d.polygon([(cx - u * 0.18, cy + u * 0.26 - a), (cx - u * 0.18 - a * 1.2, cy + u * 0.26),
                   (cx - u * 0.18, cy + u * 0.26 + a)], fill=255)
    elif kind == "thumb":
        d.rounded_rectangle((cx - u * 0.5, cy - u * 0.02, cx - u * 0.26, cy + u * 0.5), radius=u * 0.06, fill=255)
        d.rounded_rectangle((cx - u * 0.2, cy - u * 0.08, cx + u * 0.46, cy + u * 0.5), radius=u * 0.12, fill=255)
        d.polygon([(cx - u * 0.2, cy + u * 0.02), (cx - u * 0.04, cy - u * 0.46),
                   (cx + u * 0.16, cy - u * 0.4), (cx + u * 0.12, cy - u * 0.04)], fill=255)
        d.ellipse((cx - u * 0.06, cy - u * 0.58, cx + u * 0.18, cy - u * 0.34), fill=255)
    elif kind == "clock":
        r = u * 0.5
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=255, width=int(u * 0.1))
        d.line([(cx, cy), (cx, cy - u * 0.3)], fill=255, width=int(u * 0.09))
        d.line([(cx, cy), (cx + u * 0.22, cy + u * 0.1)], fill=255, width=int(u * 0.09))
        d.ellipse((cx - u * 0.07, cy - u * 0.07, cx + u * 0.07, cy + u * 0.07), fill=255)
    elif kind == "group":
        bx = cx + u * 0.2  # arkadaki kisi
        d.ellipse((bx - u * 0.16, cy - u * 0.5, bx + u * 0.16, cy - u * 0.18), fill=255)
        d.pieslice((bx - u * 0.32, cy - u * 0.1, bx + u * 0.32, cy + u * 0.56), 180, 360, fill=255)
        fx = cx - u * 0.12  # ondeki kisi, arkadakinden boslukla ayrilir
        g = u * 0.06
        d.ellipse((fx - u * 0.2 - g, cy - u * 0.4 - g, fx + u * 0.2 + g, cy + g), fill=0)
        d.pieslice((fx - u * 0.4 - g, cy + u * 0.06 - g, fx + u * 0.4 + g, cy + u * 0.86 + g), 180, 360, fill=0)
        d.ellipse((fx - u * 0.2, cy - u * 0.4, fx + u * 0.2, cy), fill=255)
        d.pieslice((fx - u * 0.4, cy + u * 0.06, fx + u * 0.4, cy + u * 0.86), 180, 360, fill=255)
    elif kind == "note":
        d.ellipse((cx - u * 0.42, cy + u * 0.12, cx - u * 0.06, cy + u * 0.42), fill=255)
        d.rectangle((cx - u * 0.13, cy - u * 0.48, cx - u * 0.04, cy + u * 0.3), fill=255)
        d.polygon([(cx - u * 0.13, cy - u * 0.48), (cx + u * 0.32, cy - u * 0.3),
                   (cx + u * 0.32, cy - u * 0.12), (cx - u * 0.04, cy - u * 0.28)], fill=255)
    elif kind == "sparkle":
        def astroid(x0, y0, r):
            return [(x0 + r * math.cos(t) ** 3, y0 + r * math.sin(t) ** 3)
                    for t in [2 * math.pi * i / 200 for i in range(200)]]
        d.polygon(astroid(cx - u * 0.08, cy + u * 0.08, u * 0.5), fill=255)
        d.polygon(astroid(cx + u * 0.36, cy - u * 0.36, u * 0.2), fill=255)
    elif kind == "key":
        r = u * 0.24
        kx, ky = cx - u * 0.26, cy
        d.ellipse((kx - r, ky - r, kx + r, ky + r), fill=255)
        d.ellipse((kx - r * 0.42, ky - r * 0.42, kx + r * 0.42, ky + r * 0.42), fill=0)
        d.rectangle((kx + r * 0.8, ky - u * 0.06, cx + u * 0.5, ky + u * 0.06), fill=255)
        d.rectangle((cx + u * 0.2, ky, cx + u * 0.3, ky + u * 0.22), fill=255)
        d.rectangle((cx + u * 0.38, ky, cx + u * 0.48, ky + u * 0.16), fill=255)
    elif kind == "crown":
        d.polygon([(cx - u * 0.5, cy + u * 0.3), (cx - u * 0.5, cy - u * 0.22), (cx - u * 0.22, cy + u * 0.02),
                   (cx, cy - u * 0.36), (cx + u * 0.22, cy + u * 0.02), (cx + u * 0.5, cy - u * 0.22),
                   (cx + u * 0.5, cy + u * 0.3)], fill=255)
        for x, y in ((cx - u * 0.5, cy - u * 0.24), (cx, cy - u * 0.38), (cx + u * 0.5, cy - u * 0.24)):
            d.ellipse((x - u * 0.08, y - u * 0.08, x + u * 0.08, y + u * 0.08), fill=255)
        d.rounded_rectangle((cx - u * 0.5, cy + u * 0.36, cx + u * 0.5, cy + u * 0.48), radius=u * 0.04, fill=255)
    elif kind == "tv":
        d.rounded_rectangle((cx - u * 0.55, cy - u * 0.42, cx + u * 0.55, cy + u * 0.3), radius=u * 0.1, fill=255)
        d.rounded_rectangle((cx - u * 0.45, cy - u * 0.32, cx + u * 0.45, cy + u * 0.2), radius=u * 0.05, fill=0)
        d.polygon([(cx - u * 0.1, cy - u * 0.2), (cx - u * 0.1, cy + u * 0.08), (cx + u * 0.15, cy - u * 0.06)], fill=255)
        d.rounded_rectangle((cx - u * 0.25, cy + u * 0.4, cx + u * 0.25, cy + u * 0.48), radius=u * 0.04, fill=255)
    elif kind == "shield":
        d.polygon([(cx, cy - u * 0.55), (cx + u * 0.45, cy - u * 0.38), (cx + u * 0.42, cy + u * 0.05),
                   (cx, cy + u * 0.55), (cx - u * 0.42, cy + u * 0.05), (cx - u * 0.45, cy - u * 0.38)], fill=255)
        d.line([(cx - u * 0.2, cy), (cx - u * 0.04, cy + u * 0.16), (cx + u * 0.22, cy - u * 0.14)],
               fill=0, width=int(u * 0.1), joint="curve")
    elif kind == "cloud":
        for x, y, r in ((-0.22, 0.05, 0.25), (0.08, -0.12, 0.33), (0.32, 0.08, 0.22)):
            d.ellipse((cx + u * (x - r), cy + u * (y - r), cx + u * (x + r), cy + u * (y + r)), fill=255)
        d.rounded_rectangle((cx - u * 0.47, cy + u * 0.02, cx + u * 0.54, cy + u * 0.3), radius=u * 0.14, fill=255)
    elif kind == "gamepad":
        d.rounded_rectangle((cx - u * 0.42, cy - u * 0.26, cx + u * 0.42, cy + u * 0.22), radius=u * 0.2, fill=255)
        for sx in (-1, 1):
            d.ellipse((cx + sx * u * 0.36 - u * 0.2, cy - u * 0.06, cx + sx * u * 0.36 + u * 0.2, cy + u * 0.4), fill=255)
        d.rectangle((cx - u * 0.36, cy - u * 0.04, cx - u * 0.18, cy + u * 0.02), fill=0)
        d.rectangle((cx - u * 0.3, cy - u * 0.1, cx - u * 0.24, cy + u * 0.08), fill=0)
        for bx, by in ((0.24, -0.06), (0.34, 0.04)):
            d.ellipse((cx + u * (bx - 0.05), cy + u * (by - 0.05), cx + u * (bx + 0.05), cy + u * (by + 0.05)), fill=0)
    elif kind == "gem":
        d.polygon([(cx - u * 0.5, cy - u * 0.18), (cx - u * 0.26, cy - u * 0.45), (cx + u * 0.26, cy - u * 0.45),
                   (cx + u * 0.5, cy - u * 0.18), (cx, cy + u * 0.52)], fill=255)
        w = int(u * 0.04)
        d.line([(cx - u * 0.5, cy - u * 0.18), (cx + u * 0.5, cy - u * 0.18)], fill=0, width=w)
        d.line([(cx - u * 0.12, cy - u * 0.45), (cx - u * 0.2, cy - u * 0.18), (cx, cy + u * 0.52)], fill=0, width=w)
        d.line([(cx + u * 0.12, cy - u * 0.45), (cx + u * 0.2, cy - u * 0.18), (cx, cy + u * 0.52)], fill=0, width=w)
    elif kind == "coin":
        r = u * 0.5
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
        d.ellipse((cx - r * 0.78, cy - r * 0.78, cx + r * 0.78, cy + r * 0.78), fill=0)
        d.ellipse((cx - r * 0.66, cy - r * 0.66, cx + r * 0.66, cy + r * 0.66), fill=255)
        d.polygon([(cx, cy - r * 0.42), (cx + r * 0.3, cy), (cx, cy + r * 0.42), (cx - r * 0.3, cy)], fill=0)
    elif kind == "card":
        d.rounded_rectangle((cx - u * 0.55, cy - u * 0.36, cx + u * 0.55, cy + u * 0.36), radius=u * 0.08, fill=255)
        d.rectangle((cx - u * 0.55, cy - u * 0.2, cx + u * 0.55, cy - u * 0.06), fill=0)
        d.rounded_rectangle((cx - u * 0.42, cy + u * 0.08, cx - u * 0.06, cy + u * 0.2), radius=u * 0.03, fill=0)
    elif kind == "wave":
        for k, h in enumerate((0.3, 0.62, 1.0, 0.7, 0.38)):
            x = cx - u * 0.48 + k * u * 0.22
            d.rounded_rectangle((x, cy - u * 0.5 * h, x + u * 0.12, cy + u * 0.5 * h), radius=u * 0.06, fill=255)
    elif kind == "doc":
        d.polygon([(cx - u * 0.38, cy - u * 0.5), (cx + u * 0.16, cy - u * 0.5), (cx + u * 0.38, cy - u * 0.28),
                   (cx + u * 0.38, cy + u * 0.5), (cx - u * 0.38, cy + u * 0.5)], fill=255)
        d.polygon([(cx + u * 0.12, cy - u * 0.5), (cx + u * 0.38, cy - u * 0.24), (cx + u * 0.12, cy - u * 0.24)], fill=0)
        for k in range(3):
            y = cy - u * 0.02 + k * u * 0.17
            d.rounded_rectangle((cx - u * 0.24, y, cx + u * 0.24, y + u * 0.07), radius=u * 0.03, fill=0)
    elif kind == "link":
        w = int(u * 0.1)
        for sx in (-1, 1):
            box = (cx + sx * u * 0.2 - u * 0.32, cy - u * 0.18, cx + sx * u * 0.2 + u * 0.32, cy + u * 0.18)
            d.rounded_rectangle(box, radius=u * 0.18, outline=255, width=w)
    elif kind == "pin":
        r = u * 0.34
        d.ellipse((cx - r, cy - u * 0.55, cx + r, cy - u * 0.55 + 2 * r), fill=255)
        d.polygon([(cx - r * 0.86, cy - u * 0.04), (cx + r * 0.86, cy - u * 0.04), (cx, cy + u * 0.55)], fill=255)
        d.ellipse((cx - r * 0.42, cy - u * 0.21 - r * 0.42, cx + r * 0.42, cy - u * 0.21 + r * 0.42), fill=0)
    elif kind == "layers":
        for k, dy in enumerate((0.26, 0.0, -0.26)):
            if k:
                d.polygon([(cx - u * 0.52, cy + u * dy + 0.06 * u), (cx, cy + u * dy - u * 0.2 + 0.06 * u),
                           (cx + u * 0.52, cy + u * dy + 0.06 * u), (cx, cy + u * dy + u * 0.32 + 0.06 * u)], fill=0)
            d.polygon([(cx - u * 0.5, cy + u * dy), (cx, cy + u * dy - u * 0.24),
                       (cx + u * 0.5, cy + u * dy), (cx, cy + u * dy + u * 0.24)], fill=255)
    else:
        raise ValueError(kind)
    return m


# ---------------------------------------------------------------------------
# Yazi ve rozetler
# ---------------------------------------------------------------------------


def font(path, size):
    return ImageFont.truetype(path, size)


def fit_font(text, path, max_w, start):
    size = start
    while size > 60:
        f = font(path, size)
        if f.getlength(text) <= max_w:
            return f
        size -= 8
    return font(path, size)


def draw_center_text(img, text, f, cy, fill, shadow=True):
    d = ImageDraw.Draw(img)
    box = d.textbbox((0, 0), text, font=f)
    w, h = box[2] - box[0], box[3] - box[1]
    x, y = (S - w) / 2 - box[0], cy - h / 2 - box[1]
    if shadow:
        sh = Image.new("L", (S, S), 0)
        ImageDraw.Draw(sh).text((x, y + 14), text, font=f, fill=110)
        sh = sh.filter(ImageFilter.GaussianBlur(16))
        img.paste((0, 0, 0), (0, 0), sh)
    d.text((x, y), text, font=f, fill=fill)


def draw_badge(img, text, cy):
    color = FOREIGN_BLUE if text == "YABANCI" else TR_RED
    f = font(FONT_BLACK, 104)
    d = ImageDraw.Draw(img)
    tw = d.textlength(text, font=f)
    emblem = 150
    w = tw + emblem + 150
    x0, y0, x1, y1 = (S - w) / 2, cy - 92, (S + w) / 2, cy + 92
    d.rounded_rectangle((x0, y0, x1, y1), radius=92, fill=color)
    ex, ey = x0 + 70 + emblem / 2, cy
    if text == "YABANCI":
        r = 58
        d.ellipse((ex - r, ey - r, ex + r, ey + r), outline="white", width=12)
        d.ellipse((ex - r * 0.45, ey - r, ex + r * 0.45, ey + r), outline="white", width=10)
        d.line((ex - r, ey, ex + r, ey), fill="white", width=10)
    else:  # ay yildiz
        r = 60
        d.ellipse((ex - r, ey - r, ex + r, ey + r), fill="white")
        r2, off = r * 0.8, r * 0.28
        d.ellipse((ex - r2 + off, ey - r2, ex + r2 + off, ey + r2), fill=color)
        # Yildizin bir ucu hilale bakar (sola).
        sx, sy, so, si = ex + r * 0.62, ey, r * 0.36, r * 0.14
        pts = [
            (sx + (so if k % 2 == 0 else si) * math.cos(math.pi + k * math.pi / 5),
             sy + (so if k % 2 == 0 else si) * math.sin(math.pi + k * math.pi / 5))
            for k in range(10)
        ]
        d.polygon(pts, fill="white")
    box = d.textbbox((0, 0), text, font=f)
    d.text((x0 + 70 + emblem + 30 - box[0], cy - (box[3] - box[1]) / 2 - box[1]), text, font=f, fill="white")


def draw_platform_pill(img, label, dark):
    # Kutuphane seciminde kucuk gorunur: yazi buyuk tutulur.
    f = font(FONT_BLACK, 132)
    d = ImageDraw.Draw(img, "RGBA")
    tw = d.textlength(label, font=f)
    w = tw + 170
    x0, y0, x1, y1 = (S - w) / 2, 90, (S + w) / 2, 320
    d.rounded_rectangle((x0, y0, x1, y1), radius=115,
                        fill=(255, 255, 255, 38) if not dark else (255, 255, 255, 30),
                        outline=(255, 255, 255, 120), width=6)
    box = d.textbbox((0, 0), label, font=f)
    d.text(((S - (box[2] - box[0])) / 2 - box[0], 205 - (box[3] - box[1]) / 2 - box[1]),
           label, font=f, fill="white")


# ---------------------------------------------------------------------------


def render(platform, icon, label, badge):
    cfg = PLATFORMS[platform]
    img = background(cfg["bg"])
    draw_platform_pill(img, cfg["label"], cfg["bg"][0] == "glow")

    cx, cy, r = S / 2, 820, 400
    shadow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shadow).ellipse((cx - r, cy - r + 30, cx + r, cy + r + 30), fill=120)
    img.paste((0, 0, 0), (0, 0), shadow.filter(ImageFilter.GaussianBlur(40)))
    ImageDraw.Draw(img).ellipse((cx - r, cy - r, cx + r, cy + r), fill="white")

    u = 470
    mask = icon_mask(icon, cx, cy, u)
    if cfg["icon"] == "gradient":
        img.paste(background(cfg["bg"]), (0, 0), mask)
    elif cfg["icon"] == "glitch":
        d = 16
        img.paste(TT_CYAN, (0, 0), ImageChops.offset(mask, -d, -d))
        img.paste(TT_RED, (0, 0), ImageChops.offset(mask, d, d))
        img.paste((20, 20, 24), (0, 0), mask)
    else:
        img.paste(cfg["icon"], (0, 0), mask)

    if badge:
        draw_badge(img, badge, 1355)
        label_cy = 1640
    else:
        label_cy = 1500
    f = fit_font(label, FONT_BLACK, S - 260, 250)
    draw_center_text(img, label, f, label_cy, "white")
    return img.resize((FINAL, FINAL), Image.LANCZOS)


def render_account(title, plan, duration, tag, icon, stops):
    """Hesap / abonelik / lisans karti: sola yasli buyuk ad, plan, sure rozeti."""
    img = diagonal_gradient(stops)
    # Acik renkli ilk durak yaziyi rozette okunur kilar; koyu kartlarda siyah.
    accent = stops[0][1] if sum(stops[0][1]) < 600 and sum(stops[0][1]) > 200 else (20, 20, 26)

    watermark = icon_mask(icon, 1480, 1420, 1250).point(lambda v: v * 0.11)
    img.paste((255, 255, 255), (0, 0), watermark)

    d = ImageDraw.Draw(img, "RGBA")
    left = 150
    f_tag = font(FONT_BOLD, 84)
    tw = d.textlength(tag, font=f_tag)
    d.rounded_rectangle((left, 140, left + tw + 120, 290), radius=75,
                        fill=(255, 255, 255, 40), outline=(255, 255, 255, 130), width=5)
    box = d.textbbox((0, 0), tag, font=f_tag)
    d.text((left + 60 - box[0], 215 - (box[3] - box[1]) / 2 - box[1]), tag, font=f_tag, fill="white")

    tile = (left, 400, left + 400, 800)
    shadow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((tile[0], tile[1] + 24, tile[2], tile[3] + 24), radius=90, fill=110)
    img.paste((0, 0, 0), (0, 0), shadow.filter(ImageFilter.GaussianBlur(30)))
    d.rounded_rectangle(tile, radius=90, fill="white")
    img.paste(accent, (0, 0), icon_mask(icon, (tile[0] + tile[2]) / 2, (tile[1] + tile[3]) / 2, 280))

    f_title = fit_font(title, FONT_BLACK, S - 2 * left, 290)
    box = d.textbbox((0, 0), title, font=f_title)
    d.text((left - box[0], 1010 - (box[3] - box[1]) / 2 - box[1]), title, font=f_title, fill="white")
    f_plan = fit_font(plan, FONT_BOLD, S - 2 * left, 190)
    box = d.textbbox((0, 0), plan, font=f_plan)
    d.text((left - box[0], 1250 - (box[3] - box[1]) / 2 - box[1]), plan, font=f_plan,
           fill=(255, 255, 255, 215))

    f_dur = font(FONT_BLACK, 200)
    box = d.textbbox((0, 0), duration, font=f_dur)
    w, h = box[2] - box[0], box[3] - box[1]
    y0, y1 = 1500, 1800
    shadow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((left, y0 + 24, left + w + 180, y1 + 24), radius=70, fill=100)
    img.paste((0, 0, 0), (0, 0), shadow.filter(ImageFilter.GaussianBlur(30)))
    d.rounded_rectangle((left, y0, left + w + 180, y1), radius=70, fill="white")
    d.text((left + 90 - box[0], (y0 + y1) / 2 - h / 2 - box[1]), duration, font=f_dur, fill=accent)
    return img.resize((FINAL, FINAL), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Tasarim 3: paket karti (buzlu cam, buyuk sayi)
# ---------------------------------------------------------------------------

# (platform, ad, simge, sayi, etiket, alt yazi, rozet, ek kelimeler)
PACKAGES = [
    ("instagram", "Instagram 1000 Takipçi", "follow", "+1K", "TAKİPÇİ", "1.000 ADET", None, "takipçi, 1k, 1000, bin"),
    ("instagram", "Instagram 5000 Takipçi", "follow", "+5K", "TAKİPÇİ", "5.000 ADET", None, "takipçi, 5k, 5000"),
    ("instagram", "Instagram 10000 Takipçi", "follow", "+10K", "TAKİPÇİ", "10.000 ADET", None, "takipçi, 10k, 10000, on bin"),
    ("instagram", "Instagram 1000 Türk Takipçi", "follow", "+1K", "TAKİPÇİ", None, "TÜRK", "takipçi, türk, 1k, 1000"),
    ("instagram", "Instagram 1000 Beğeni", "heart", "+1K", "BEĞENİ", "1.000 ADET", None, "beğeni, like, 1k, 1000"),
    ("instagram", "Instagram 5000 Beğeni", "heart", "+5K", "BEĞENİ", "5.000 ADET", None, "beğeni, like, 5k, 5000"),
    ("instagram", "Instagram 10000 İzlenme", "eye", "+10K", "İZLENME", "10.000 ADET", None, "izlenme, reels, 10k, 10000"),
    ("instagram", "Instagram 100000 İzlenme", "eye", "+100K", "İZLENME", "100.000 ADET", None, "izlenme, reels, 100k, 100000"),
    ("tiktok", "TikTok 1000 Takipçi", "follow", "+1K", "TAKİPÇİ", "1.000 ADET", None, "takipçi, 1k, 1000"),
    ("tiktok", "TikTok 5000 Takipçi", "follow", "+5K", "TAKİPÇİ", "5.000 ADET", None, "takipçi, 5k, 5000"),
    ("tiktok", "TikTok 10000 Takipçi", "follow", "+10K", "TAKİPÇİ", "10.000 ADET", None, "takipçi, 10k, 10000"),
    ("tiktok", "TikTok 1000 Beğeni", "heart", "+1K", "BEĞENİ", "1.000 ADET", None, "beğeni, like, 1k, 1000"),
    ("tiktok", "TikTok 10000 Beğeni", "heart", "+10K", "BEĞENİ", "10.000 ADET", None, "beğeni, like, 10k, 10000"),
    ("tiktok", "TikTok 10000 İzlenme", "play", "+10K", "İZLENME", "10.000 ADET", None, "izlenme, video, 10k, 10000"),
    ("tiktok", "TikTok 100000 İzlenme", "play", "+100K", "İZLENME", "100.000 ADET", None, "izlenme, video, 100k, 100000"),
    ("youtube", "YouTube 1000 Abone", "follow", "+1K", "ABONE", "1.000 ADET", None, "abone, subscriber, 1k, 1000"),
    ("youtube", "YouTube 10000 İzlenme", "play", "+10K", "İZLENME", "10.000 ADET", None, "izlenme, video, 10k, 10000"),
    ("youtube", "YouTube 100000 İzlenme", "play", "+100K", "İZLENME", "100.000 ADET", None, "izlenme, video, 100k, 100000"),
    ("youtube", "YouTube 4000 Saat İzlenme", "clock", "4000", "İZLENME SAATİ", "PARA KAZANMA PAKETİ", None, "izlenme saati, 4000 saat, para kazanma, watch time"),
    ("x", "X (Twitter) 1000 Takipçi", "follow", "+1K", "TAKİPÇİ", "1.000 ADET", None, "takipçi, 1k, 1000"),
    ("x", "X (Twitter) 1000 Beğeni", "heart", "+1K", "BEĞENİ", "1.000 ADET", None, "beğeni, like, 1k, 1000"),
    ("x", "X (Twitter) 100000 Görüntülenme", "chart", "+100K", "GÖRÜNTÜLENME", "100.000 ADET", None, "görüntülenme, view, 100k"),
    ("telegram", "Telegram 1000 Üye", "group", "+1K", "KANAL ÜYE", "1.000 ADET", None, "üye, kanal, 1k, 1000"),
    ("telegram", "Telegram 10000 Üye", "group", "+10K", "KANAL ÜYE", "10.000 ADET", None, "üye, kanal, 10k, 10000"),
    ("spotify", "Spotify 10000 Dinlenme", "note", "+10K", "DİNLENME", "10.000 ADET", None, "dinlenme, stream, 10k, 10000"),
]


def frosted(img, box, radius, tint=0.16):
    """Kutunun altini bulaniklastirip beyaza cekerek buzlu cam yapar."""
    blurred = img.filter(ImageFilter.GaussianBlur(60))
    glass = Image.blend(blurred, Image.new("RGB", (S, S), (255, 255, 255)), tint)
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    img.paste(glass, (0, 0), m)
    ImageDraw.Draw(img, "RGBA").rounded_rectangle(box, radius=radius, outline=(255, 255, 255, 120), width=6)


def render_package(platform, icon, count, label, sub, badge):
    cfg = PLATFORMS[platform]
    img = background(cfg["bg"])
    # Cama derinlik: arkada buyuk yari saydam simge.
    img.paste((255, 255, 255), (0, 0), icon_mask(icon, 1550, 560, 900).point(lambda v: v * 0.16))
    draw_platform_pill(img, cfg["label"], cfg["bg"][0] == "glow")
    frosted(img, (170, 390, 1830, 1850), 110)

    cx, cy, r = S / 2, 640, 165
    d = ImageDraw.Draw(img)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill="white")
    mask = icon_mask(icon, cx, cy, 200)
    if cfg["icon"] == "gradient":
        img.paste(background(cfg["bg"]), (0, 0), mask)
    elif cfg["icon"] == "glitch":
        img.paste(TT_CYAN, (0, 0), ImageChops.offset(mask, -8, -8))
        img.paste(TT_RED, (0, 0), ImageChops.offset(mask, 8, 8))
        img.paste((20, 20, 24), (0, 0), mask)
    else:
        img.paste(cfg["icon"], (0, 0), mask)

    f_count = fit_font(count, FONT_BLACK, 1400, 470)
    draw_center_text(img, count, f_count, 1080, "white")
    draw_center_text(img, label, fit_font(label, FONT_BLACK, 1440, 190), 1400, "white")
    if badge:
        draw_badge(img, badge, 1650)
    elif sub:
        f_sub = fit_font(sub, FONT_BOLD, 1300, 96)
        dd = ImageDraw.Draw(img, "RGBA")
        tw = dd.textlength(sub, font=f_sub)
        dd.rounded_rectangle(((S - tw) / 2 - 60, 1590, (S + tw) / 2 + 60, 1720), radius=65,
                             fill=(0, 0, 0, 60))
        draw_center_text(img, sub, f_sub, 1655, (255, 255, 255), shadow=False)
    return img.resize((FINAL, FINAL), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Tasarim 4: neon
# ---------------------------------------------------------------------------

NEON_PLATFORMS = {
    "linkedin": ("LinkedIn", (10, 132, 255), "linkedin, iş, kariyer, profesyonel, sosyal medya"),
    "pinterest": ("Pinterest", (255, 40, 70), "pinterest, pin, sosyal medya"),
    "kick": ("Kick", (83, 252, 24), "kick, yayın, yayıncı, sosyal medya"),
    "discord": ("Discord", (114, 137, 255), "discord, sunucu, server, sosyal medya"),
    "whatsapp": ("WhatsApp", (37, 211, 102), "whatsapp, kanal, sosyal medya"),
    "soundcloud": ("SoundCloud", (255, 120, 20), "soundcloud, müzik, şarkı, sosyal medya"),
    "snapchat": ("Snapchat", (255, 236, 0), "snapchat, snap, sosyal medya"),
    "instagram": ("Instagram", (255, 70, 170), PLATFORMS["instagram"]["words"]),
    "tiktok": ("TikTok", (37, 244, 238), PLATFORMS["tiktok"]["words"]),
    "youtube": ("YouTube", (255, 50, 70), PLATFORMS["youtube"]["words"]),
    "x": ("X (Twitter)", (220, 230, 255), PLATFORMS["x"]["words"]),
}

# (platform, dosya adi, urun adi, simge, etiket, ek kelimeler)
NEON = [
    ("linkedin", "LinkedIn Takipçi", "LinkedIn Takipçi", "follow", "TAKİPÇİ", "takipçi, follower"),
    ("linkedin", "LinkedIn Bağlantı", "LinkedIn Bağlantı", "link", "BAĞLANTI", "bağlantı, connection, ağ"),
    ("linkedin", "LinkedIn Beğeni", "LinkedIn Beğeni", "thumb", "BEĞENİ", "beğeni, like, gönderi"),
    ("pinterest", "Pinterest Takipçi", "Pinterest Takipçi", "follow", "TAKİPÇİ", "takipçi, follower"),
    ("pinterest", "Pinterest Pin Kaydetme", "Pinterest Pin Kaydetme", "pin", "PİN KAYDETME", "pin, kaydetme, save"),
    ("kick", "Kick Takipçi", "Kick Takipçi", "follow", "TAKİPÇİ", "takipçi, follower"),
    ("kick", "Kick Canlı İzleyici", "Kick Canlı İzleyici", "live", "CANLI İZLEYİCİ", "canlı, izleyici, viewer"),
    ("discord", "Discord Sunucu Üye", "Discord Sunucu Üye", "group", "SUNUCU ÜYE", "üye, member, sunucu"),
    ("discord", "Discord Online Üye", "Discord Online Üye", "live", "ONLINE ÜYE", "online, çevrimiçi, üye"),
    ("whatsapp", "WhatsApp Kanal Takipçi", "WhatsApp Kanal Takipçi", "follow", "KANAL TAKİPÇİ", "kanal, takipçi"),
    ("soundcloud", "SoundCloud Dinlenme", "SoundCloud Dinlenme", "wave", "DİNLENME", "dinlenme, play, stream"),
    ("soundcloud", "SoundCloud Takipçi", "SoundCloud Takipçi", "follow", "TAKİPÇİ", "takipçi, follower"),
    ("snapchat", "Snapchat Takipçi", "Snapchat Takipçi", "follow", "TAKİPÇİ", "takipçi, arkadaş, follower"),
    ("snapchat", "Snapchat Görüntülenme", "Snapchat Görüntülenme", "eye", "GÖRÜNTÜLENME", "görüntülenme, hikaye, story"),
    # Ana platformlarin sik alternatifi: ayni urun adi, farkli dosya (kimlik) adi.
    ("instagram", "Instagram Takipçi - Neon", "Instagram Takipçi", "follow", "TAKİPÇİ", "takipçi, follower"),
    ("instagram", "Instagram Beğeni - Neon", "Instagram Beğeni", "heart", "BEĞENİ", "beğeni, like"),
    ("tiktok", "TikTok Takipçi - Neon", "TikTok Takipçi", "follow", "TAKİPÇİ", "takipçi, follower"),
    ("tiktok", "TikTok Beğeni - Neon", "TikTok Beğeni", "heart", "BEĞENİ", "beğeni, like"),
    ("youtube", "YouTube Abone - Neon", "YouTube Abone", "follow", "ABONE", "abone, subscriber"),
    ("x", "X (Twitter) Takipçi - Neon", "X (Twitter) Takipçi", "follow", "TAKİPÇİ", "takipçi, follower"),
]


def neon_glow(img, mask, color, radii=((70, 0.9), (26, 1.0))):
    """Maskenin cevresine renkli parilti ekler (toplamali)."""
    for r, strength in radii:
        g = mask.filter(ImageFilter.GaussianBlur(r)).point(lambda v: min(255, int(v * strength * 1.6)))
        layer = Image.new("RGB", (S, S), (0, 0, 0))
        layer.paste(color, (0, 0), g)
        img = ImageChops.add(img, layer)
    return img


def render_neon(platform, icon, label):
    name, color, _ = NEON_PLATFORMS[platform]
    img = Image.new("RGB", (S, S), (6, 6, 10))
    # Ince izgara + ortada hafif renkli sis.
    grid = Image.new("L", (S, S), 0)
    gd = ImageDraw.Draw(grid)
    for k in range(0, S, 100):
        gd.line([(k, 0), (k, S)], fill=14, width=2)
        gd.line([(0, k), (S, k)], fill=14, width=2)
    img.paste((255, 255, 255), (0, 0), grid)
    haze = Image.new("L", (S, S), 0)
    ImageDraw.Draw(haze).ellipse((300, 250, 1700, 1350), fill=70)
    img = neon_glow(img, haze.filter(ImageFilter.GaussianBlur(250)), color, radii=((1, 0.5),))

    # Platform adi: ust ortada, harf aralikli, neon.
    f_p = font(FONT_BOLD, 120)
    spaced = " ".join(name.upper().replace("İ", "I")) if len(name) <= 9 else name.upper()
    tmask = Image.new("L", (S, S), 0)
    td = ImageDraw.Draw(tmask)
    box = td.textbbox((0, 0), spaced, font=f_p)
    td.text(((S - (box[2] - box[0])) / 2 - box[0], 230 - (box[3] - box[1]) / 2 - box[1]), spaced, font=f_p, fill=255)
    img = neon_glow(img, tmask, color, radii=((30, 0.8),))
    img.paste(color, (0, 0), tmask)

    cx, cy, r = S / 2, 860, 430
    ring = Image.new("L", (S, S), 0)
    ImageDraw.Draw(ring).ellipse((cx - r, cy - r, cx + r, cy + r), outline=255, width=16)
    mask = icon_mask(icon, cx, cy, 480)
    both = ImageChops.lighter(ring, mask)
    img = neon_glow(img, both, color)
    img.paste(color, (0, 0), ring)
    img.paste(color, (0, 0), mask)
    # Neon tupun beyaz cekirdegi
    core = mask.filter(ImageFilter.MinFilter(15)).filter(ImageFilter.GaussianBlur(6)).point(lambda v: v * 0.55)
    img.paste((255, 255, 255), (0, 0), core)

    f_l = fit_font(label, FONT_BLACK, S - 280, 230)
    lmask = Image.new("L", (S, S), 0)
    ld = ImageDraw.Draw(lmask)
    box = ld.textbbox((0, 0), label, font=f_l)
    ld.text(((S - (box[2] - box[0])) / 2 - box[0], 1620 - (box[3] - box[1]) / 2 - box[1]), label, font=f_l, fill=255)
    img = neon_glow(img, lmask, color, radii=((40, 0.9),))
    img.paste((255, 255, 255), (0, 0), lmask)
    return img.resize((FINAL, FINAL), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Tasarim 5: premium kart (koyu, kosede capraz sure seridi)
# ---------------------------------------------------------------------------

STREAM, AI2, SOFT, VPN, GAME = "DİZİ & FİLM / MÜZİK", "YAPAY ZEKÂ", "YAZILIM", "VPN", "OYUN"

# (ad, baslik, plan, serit, kategori, simge, marka rengi, kelimeler)
PREMIUM = [
    ("Netflix Premium 1 Aylık", "Netflix", "Premium", "1 AY", STREAM, "tv", (229, 9, 20), "netflix, dizi, film, premium"),
    ("Disney+ 1 Aylık", "Disney+", "Standart", "1 AY", STREAM, "tv", (40, 90, 230), "disney, disney plus, dizi, film"),
    ("Prime Video 1 Aylık", "Prime Video", "Amazon", "1 AY", STREAM, "tv", (0, 168, 225), "amazon prime, prime video, dizi, film"),
    ("HBO Max 1 Aylık", "HBO Max", "Standart", "1 AY", STREAM, "tv", (60, 80, 255), "hbo max, max, blutv, dizi, film"),
    ("Exxen 1 Aylık", "Exxen", "Reklamsız", "1 AY", STREAM, "tv", (255, 196, 0), "exxen, dizi, maç, spor"),
    ("Gain 1 Aylık", "Gain", "Abonelik", "1 AY", STREAM, "tv", (255, 70, 120), "gain, dizi, film"),
    ("Spotify Premium Aile 1 Aylık", "Spotify", "Premium Aile", "1 AY", STREAM, "note", (29, 185, 84), "spotify, premium, aile, family, müzik"),
    ("YouTube Premium Aile 1 Aylık", "YouTube", "Premium Aile", "1 AY", STREAM, "play", (255, 30, 50), "youtube, premium, aile, family, reklamsız"),
    ("Apple Music 1 Aylık", "Apple Music", "Bireysel", "1 AY", STREAM, "note", (250, 45, 72), "apple music, müzik"),
    ("Claude Max 1 Aylık", "Claude", "Max", "1 AY", AI2, "sparkle", (217, 119, 87), "claude, anthropic, max, yapay zeka"),
    ("Google AI Ultra 1 Aylık", "Google AI", "Ultra", "1 AY", AI2, "sparkle", (110, 120, 255), "gemini, google ai ultra, ultra, yapay zeka"),
    ("ChatGPT Plus 6 Aylık", "ChatGPT", "Plus", "6 AY", AI2, "sparkle", (16, 163, 127), "chatgpt, openai, plus, 6 ay, yapay zeka"),
    ("ElevenLabs Creator 1 Aylık", "ElevenLabs", "Creator", "1 AY", AI2, "wave", (180, 180, 200), "elevenlabs, seslendirme, ses, yapay zeka"),
    ("Suno Pro 1 Aylık", "Suno", "Pro", "1 AY", AI2, "note", (255, 130, 60), "suno, müzik üretme, şarkı, yapay zeka"),
    ("Runway Standard 1 Aylık", "Runway", "Standard", "1 AY", AI2, "play", (200, 200, 215), "runway, video üretme, yapay zeka"),
    ("Leonardo AI 1 Aylık", "Leonardo AI", "Apprentice", "1 AY", AI2, "sparkle", (150, 90, 255), "leonardo, görsel üretme, yapay zeka"),
    ("Kling AI 1 Aylık", "Kling AI", "Standard", "1 AY", AI2, "play", (60, 210, 160), "kling, video üretme, yapay zeka"),
    ("Grammarly Premium 12 Aylık", "Grammarly", "Premium", "12 AY", AI2, "doc", (21, 194, 107), "grammarly, ingilizce, yazım"),
    ("Notion Plus 12 Aylık", "Notion", "Plus", "12 AY", SOFT, "doc", (200, 200, 210), "notion, not, verimlilik"),
    ("Adobe Creative Cloud 1 Aylık", "Adobe CC", "Tüm Uygulamalar", "1 AY", SOFT, "layers", (250, 40, 20), "adobe, creative cloud, photoshop, illustrator"),
    ("Adobe Photoshop 1 Aylık", "Photoshop", "Adobe", "1 AY", SOFT, "layers", (49, 168, 255), "photoshop, adobe, fotoğraf düzenleme"),
    ("Google One 2 TB 12 Aylık", "Google One", "2 TB Depolama", "12 AY", SOFT, "cloud", (66, 133, 244), "google one, google drive, depolama, 2tb"),
    ("iCloud+ 200 GB 1 Aylık", "iCloud+", "200 GB", "1 AY", SOFT, "cloud", (52, 140, 246), "icloud, apple, depolama"),
    ("Office 2024 Pro Plus Lisans", "Office 2024", "Pro Plus", "LİSANS", SOFT, "key", (235, 60, 0), "office 2024, office, word, excel, lisans, key"),
    ("Windows 10 Pro Lisans", "Windows 10", "Pro", "LİSANS", SOFT, "key", (0, 120, 212), "windows 10, windows, lisans, key"),
    ("NordVPN 12 Aylık", "NordVPN", "Standart", "12 AY", VPN, "shield", (68, 116, 252), "nordvpn, vpn, gizlilik"),
    ("Surfshark VPN 12 Aylık", "Surfshark", "VPN", "12 AY", VPN, "shield", (23, 190, 187), "surfshark, vpn, gizlilik"),
    ("ExpressVPN 1 Aylık", "ExpressVPN", "VPN", "1 AY", VPN, "shield", (218, 57, 64), "expressvpn, vpn, gizlilik"),
    ("Xbox Game Pass Ultimate 1 Aylık", "Game Pass", "Ultimate", "1 AY", GAME, "gamepad", (16, 160, 16), "xbox, game pass, oyun"),
    ("PlayStation Plus Essential 12 Aylık", "PS Plus", "Essential", "12 AY", GAME, "gamepad", (0, 90, 200), "playstation, ps plus, ps4, ps5, oyun"),
    ("Steam Cüzdan Kodu 100 TL", "Steam", "Cüzdan Kodu", "100 TL", GAME, "card", (102, 192, 244), "steam, cüzdan, wallet, oyun, e-pin"),
    ("Valorant 1000 VP", "Valorant", "1000 VP", None, GAME, "coin", (255, 70, 85), "valorant, vp, valorant point, e-pin, oyun"),
    ("PUBG Mobile 660 UC", "PUBG Mobile", "660 UC", None, GAME, "coin", (242, 169, 0), "pubg, uc, pubg mobile, e-pin, oyun"),
    ("Free Fire 1080 Elmas", "Free Fire", "1080 Elmas", None, GAME, "gem", (255, 120, 0), "free fire, elmas, e-pin, oyun"),
    ("Roblox 800 Robux", "Roblox", "800 Robux", None, GAME, "coin", (200, 205, 215), "roblox, robux, e-pin, oyun"),
    ("Mobile Legends 500 Elmas", "Mobile Legends", "500 Elmas", None, GAME, "gem", (60, 130, 240), "mobile legends, mlbb, elmas, e-pin, oyun"),
    ("Brawl Stars 950 Elmas", "Brawl Stars", "950 Elmas", None, GAME, "gem", (255, 200, 0), "brawl stars, elmas, e-pin, oyun"),
    ("League of Legends 1000 RP", "League of Legends", "1000 RP", None, GAME, "coin", (200, 155, 60), "lol, league of legends, rp, riot, e-pin, oyun"),
]


def shade(color, k):
    return tuple(max(0, min(255, int(c * k))) for c in color)


def render_premium(title, plan, ribbon, category, icon, color):
    stops = [(0, shade(color, 0.42)), (0.55, (14, 14, 20)), (1, (6, 6, 10))]
    img = diagonal_gradient(stops)
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse((900, -500, 2500, 1100), fill=160)
    img = neon_glow(img, glow.filter(ImageFilter.GaussianBlur(300)), shade(color, 0.7), radii=((1, 0.6),))
    img.paste((255, 255, 255), (0, 0), icon_mask(icon, 1500, 1500, 1100).point(lambda v: v * 0.07))

    d = ImageDraw.Draw(img, "RGBA")
    left = 160
    f_cat = font(FONT_BOLD, 76)
    x = left
    for ch in category:  # harf aralikli kategori
        d.text((x, 190), ch, font=f_cat, fill=shade(color, 1.25) if sum(color) < 500 else color)
        x += d.textlength(ch, font=f_cat) + 10
    d.rounded_rectangle((left, 300, left + 160, 312), radius=6, fill=color)

    tile = (left, 420, left + 400, 820)
    tile_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(tile_mask).rounded_rectangle(tile, radius=100, fill=255)
    shadow = tile_mask.filter(ImageFilter.GaussianBlur(40)).point(lambda v: v * 0.6)
    img.paste((0, 0, 0), (0, 30), shadow)
    fill = diagonal_gradient([(0, shade(color, 1.15)), (1, shade(color, 0.6))])
    img.paste(fill, (0, 0), tile_mask)
    gloss = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gloss).ellipse((tile[0] - 200, tile[1] - 330, tile[2] + 120, tile[1] + 190), fill=55)
    img.paste((255, 255, 255), (0, 0), ImageChops.multiply(gloss, tile_mask))
    dark_icon = sum(color) > 560
    img.paste((20, 20, 26) if dark_icon else (255, 255, 255), (0, 0),
              icon_mask(icon, (tile[0] + tile[2]) / 2, (tile[1] + tile[3]) / 2, 260))

    d = ImageDraw.Draw(img, "RGBA")
    f_title = fit_font(title, FONT_BLACK, S - 2 * left, 280)
    box = d.textbbox((0, 0), title, font=f_title)
    d.text((left - box[0], 1060 - (box[3] - box[1]) / 2 - box[1]), title, font=f_title, fill="white")
    plan_color = shade(color, 1.3) if sum(color) < 450 else color
    f_plan = fit_font(plan, FONT_BLACK, S - 2 * left, 220 if ribbon else 300)
    box = d.textbbox((0, 0), plan, font=f_plan)
    plan_cy = 1330 if ribbon else 1360
    d.text((left - box[0], plan_cy - (box[3] - box[1]) / 2 - box[1]), plan, font=f_plan, fill=plan_color)
    d.rounded_rectangle((left, 1560, left + 520, 1574), radius=7, fill=(255, 255, 255, 70))
    d.rounded_rectangle((left, 1560, left + 200, 1574), radius=7, fill=color)

    if ribbon:
        band = Image.new("RGBA", (1300, 230), color + (255,))
        bd = ImageDraw.Draw(band)
        f_r = font(FONT_BLACK, 132)
        box = bd.textbbox((0, 0), ribbon, font=f_r)
        txt = (20, 20, 26) if sum(color) > 560 else (255, 255, 255)
        bd.text(((1300 - (box[2] - box[0])) / 2 - box[0], (230 - (box[3] - box[1])) / 2 - box[1]), ribbon,
                font=f_r, fill=txt)
        band = band.rotate(-45, expand=True, resample=Image.BICUBIC)
        sh = band.split()[-1].filter(ImageFilter.GaussianBlur(30)).point(lambda v: v * 0.5)
        pos = (int(S - 330 - band.width / 2), int(330 - band.height / 2))
        img.paste((0, 0, 0), (pos[0], pos[1] + 20), sh)
        img.paste(band, pos, band)
    return img.resize((FINAL, FINAL), Image.LANCZOS)


def tr_lower(text):
    return text.replace("İ", "i").replace("I", "ı").lower()


def main():
    for p in (FONT_BLACK, FONT_BOLD):
        if not os.path.exists(p):
            sys.exit(f"Yazı tipi yok: {p}")
    out_dir = os.path.join(OUT, FOLDER)
    os.makedirs(out_dir, exist_ok=True)
    thumbs, new_thumbs = [], []
    with open(os.path.join(OUT, "kelimeler.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["dosya", "ad", "kelimeler"])

        def save(file_name, img, words, product_name=None, new=False):
            img.save(os.path.join(out_dir, file_name + ".png"), optimize=True)
            w.writerow([f"{FOLDER}/{file_name}.png", product_name or file_name, words])
            thumb = img.resize((250, 250), Image.LANCZOS)
            thumbs.append(thumb)
            if new:
                new_thumbs.append(thumb)
            print(file_name)

        for platform, name, icon, label, badge, words in ITEMS:
            save(name, render(platform, icon, label, badge),
                 f"{PLATFORMS[platform]['words']}, {words}, dijital")
        for name, title, plan, duration, tag, icon, stops, words in ACCOUNTS:
            kind = {AI: "yapay zeka, ai, hesap", SUB: "premium, üyelik, abonelik, hesap",
                    LIC: "lisans, dijital anahtar"}[tag]
            save(name, render_account(title, plan, duration, tag, icon, stops),
                 f"{words}, {kind}, {tr_lower(duration)}, dijital")
        for platform, name, icon, count, label, sub, badge, words in PACKAGES:
            save(name, render_package(platform, icon, count, label, sub, badge),
                 f"{PLATFORMS[platform]['words']}, {words}, paket, dijital", new=True)
        for platform, file_name, name, icon, label, words in NEON:
            save(file_name, render_neon(platform, icon, label),
                 f"{NEON_PLATFORMS[platform][2]}, {words}, dijital", product_name=name, new=True)
        for name, title, plan, ribbon, category, icon, color, words in PREMIUM:
            extra = f", {tr_lower(ribbon)}" if ribbon else ""
            save(name, render_premium(title, plan, ribbon, category, icon, color),
                 f"{words}, {tr_lower(category)}{extra}, dijital", new=True)

    def contact_sheet(items, path):
        cols = 8
        rows = -(-len(items) // cols)
        sheet = Image.new("RGB", (cols * 260 + 10, rows * 260 + 10), (240, 240, 240))
        for i, t in enumerate(items):
            sheet.paste(t, (10 + (i % cols) * 260, 10 + (i // cols) * 260))
        sheet.save(path)

    contact_sheet(thumbs, os.path.join(OUT, "ornekler.png"))
    contact_sheet(new_thumbs, os.path.join(OUT, "ornekler_yeni.png"))
    print(f"{len(thumbs)} görsel ({len(new_thumbs)} yeni tasarım) -> {out_dir}")


if __name__ == "__main__":
    main()
