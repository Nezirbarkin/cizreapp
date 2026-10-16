#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Dijital urun gorselleri, ikinci tur: uc yeni tasarim.

  6. Telefon: platform zemininde egik telefon (soyut profil ekrani) + yuzen bildirim karti.
  7. 3D karo: acik zemin, egik parlak platform karosu, altta koyu buyuk etiket.
  8. Hediye karti: acik zemin, egik kredi karti bicimli marka karti, altta buyuk sure/tutar.

Cizim yardimcilari generate_social_service_images.py'den gelir; resmi logo yine YOK.
Dosya adlari tasarim ekiyle (" - Telefon", " - 3D", " - Kart") ilk turdan ayrilir
(source_key cakismaz); kutuphanedeki urun adi eksizdir.

    python scripts/generate_digital_images_v2.py
    python scripts/upload_product_image_library.py build/dijital_gorseller_v2 --yukle
"""

import csv
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_social_service_images as base  # noqa: E402
from generate_social_service_images import (  # noqa: E402
    FINAL, FONT_BLACK, FONT_BOLD, IG_STOPS, PLATFORMS, S, TT_CYAN, TT_RED,
    diagonal_gradient, fit_font, font, shade, tr_lower,
)

OUT = os.path.join(base.ROOT, "build", "dijital_gorseller_v2")
FOLDER = base.FOLDER
INK = (22, 22, 30)
WHITE = (255, 255, 255)

# tile: 3D karo degradesi | tint: acik zeminin rengi | ink: ust yazi | button: telefon ekranindaki dugme
P2 = {
    "instagram": {"tile": IG_STOPS, "tint": (225, 48, 108), "tint2": (250, 160, 40), "ink": (200, 30, 100),
                  "button": (0, 149, 246), "accent": "gradient", "glitch": False},
    "tiktok": {"tile": [(0, (44, 44, 50)), (1, (4, 4, 6))], "tint": (37, 244, 238), "tint2": (254, 44, 85),
               "ink": INK, "button": (254, 44, 85), "accent": (18, 18, 22), "glitch": True},
    "x": {"tile": [(0, (58, 58, 64)), (1, (0, 0, 0))], "tint": (110, 118, 130), "tint2": (60, 66, 76),
          "ink": INK, "button": (239, 243, 244), "accent": (15, 20, 25), "glitch": False},
    "facebook": {"tile": [(0, (60, 140, 255)), (1, (10, 70, 170))], "tint": (24, 119, 242),
                 "tint2": (90, 170, 255), "ink": (16, 96, 210), "button": (24, 119, 242),
                 "accent": (24, 119, 242), "glitch": False},
}

# (platform, urun adi, simge, etiket, rozet, ek kelimeler)
PHONE = [
    ("instagram", "Instagram Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("instagram", "Instagram Türk Takipçi", "follow", "TAKİPÇİ", "TÜRK", "takipçi, türk, yerli, follower"),
    ("instagram", "Instagram Beğeni", "heart", "BEĞENİ", None, "beğeni, like, kalp"),
    ("instagram", "Instagram Yorum", "comment", "YORUM", None, "yorum, comment"),
    ("instagram", "Instagram Reels İzlenme", "reels", "REELS İZLENME", None, "reels, izlenme, video, view"),
    ("instagram", "Instagram Hikaye İzlenme", "story", "HİKAYE İZLENME", None, "hikaye, story, izlenme"),
    ("instagram", "Instagram Kaydetme", "bookmark", "KAYDETME", None, "kaydet, kaydetme, save"),
    ("tiktok", "TikTok Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("tiktok", "TikTok Türk Takipçi", "follow", "TAKİPÇİ", "TÜRK", "takipçi, türk, yerli, follower"),
    ("tiktok", "TikTok Beğeni", "heart", "BEĞENİ", None, "beğeni, like, kalp"),
    ("tiktok", "TikTok İzlenme", "play", "İZLENME", None, "izlenme, video, view"),
    ("tiktok", "TikTok Yorum", "comment", "YORUM", None, "yorum, comment"),
    ("tiktok", "TikTok Paylaşım", "share", "PAYLAŞIM", None, "paylaşım, share"),
    ("x", "X (Twitter) Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("x", "X (Twitter) Beğeni", "heart", "BEĞENİ", None, "beğeni, like, fav"),
    ("x", "X (Twitter) Retweet", "repost", "RETWEET", None, "retweet, rt, repost, yeniden paylaş"),
    ("x", "X (Twitter) Görüntülenme", "chart", "GÖRÜNTÜLENME", None, "görüntülenme, gösterim, view"),
    ("x", "X (Twitter) Yorum", "comment", "YORUM", None, "yorum, yanıt, reply"),
    ("facebook", "Facebook Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("facebook", "Facebook Sayfa Beğeni", "thumb", "SAYFA BEĞENİ", None, "sayfa beğeni, like, sayfa"),
    ("facebook", "Facebook Gönderi Beğeni", "thumb", "GÖNDERİ BEĞENİ", None, "gönderi beğeni, like, post"),
    ("facebook", "Facebook Video İzlenme", "play", "VİDEO İZLENME", None, "video, izlenme, view"),
    ("facebook", "Facebook Yorum", "comment", "YORUM", None, "yorum, comment"),
    ("facebook", "Facebook Paylaşım", "share", "PAYLAŞIM", None, "paylaşım, share"),
]

STICKER = [
    ("instagram", "Instagram Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("instagram", "Instagram Türk Takipçi", "follow", "TAKİPÇİ", "TÜRK", "takipçi, türk, yerli, follower"),
    ("instagram", "Instagram Yabancı Takipçi", "follow", "TAKİPÇİ", "YABANCI", "takipçi, yabancı, global, follower"),
    ("instagram", "Instagram Beğeni", "heart", "BEĞENİ", None, "beğeni, like, kalp"),
    ("instagram", "Instagram Türk Beğeni", "heart", "BEĞENİ", "TÜRK", "beğeni, türk, yerli, like"),
    ("instagram", "Instagram Yorum", "comment", "YORUM", None, "yorum, comment"),
    ("instagram", "Instagram İzlenme", "eye", "İZLENME", None, "izlenme, video, view"),
    ("instagram", "Instagram Paylaşım", "share", "PAYLAŞIM", None, "paylaşım, gönder, share"),
    ("instagram", "Instagram Canlı Yayın İzleyici", "live", "CANLI YAYIN", None, "canlı yayın, izleyici, live"),
    ("tiktok", "TikTok Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("tiktok", "TikTok Türk Takipçi", "follow", "TAKİPÇİ", "TÜRK", "takipçi, türk, yerli, follower"),
    ("tiktok", "TikTok Beğeni", "heart", "BEĞENİ", None, "beğeni, like, kalp"),
    ("tiktok", "TikTok İzlenme", "play", "İZLENME", None, "izlenme, video, view"),
    ("tiktok", "TikTok Kaydetme", "bookmark", "KAYDETME", None, "kaydet, favori, save"),
    ("tiktok", "TikTok Canlı Yayın İzleyici", "live", "CANLI YAYIN", None, "canlı yayın, izleyici, live"),
    ("x", "X (Twitter) Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("x", "X (Twitter) Türk Takipçi", "follow", "TAKİPÇİ", "TÜRK", "takipçi, türk, yerli, follower"),
    ("x", "X (Twitter) Beğeni", "heart", "BEĞENİ", None, "beğeni, like, fav"),
    ("x", "X (Twitter) Retweet", "repost", "RETWEET", None, "retweet, rt, repost"),
    ("x", "X (Twitter) Görüntülenme", "chart", "GÖRÜNTÜLENME", None, "görüntülenme, gösterim, view"),
    ("x", "X (Twitter) Yer İşareti", "bookmark", "YER İŞARETİ", None, "yer işareti, kaydet, bookmark"),
    ("facebook", "Facebook Takipçi", "follow", "TAKİPÇİ", None, "takipçi, follower"),
    ("facebook", "Facebook Türk Takipçi", "follow", "TAKİPÇİ", "TÜRK", "takipçi, türk, yerli, follower"),
    ("facebook", "Facebook Sayfa Beğeni", "thumb", "SAYFA BEĞENİ", None, "sayfa beğeni, like, sayfa"),
    ("facebook", "Facebook Gönderi Beğeni", "thumb", "GÖNDERİ BEĞENİ", None, "gönderi beğeni, like, post"),
    ("facebook", "Facebook Yorum", "comment", "YORUM", None, "yorum, comment"),
    ("facebook", "Facebook Paylaşım", "share", "PAYLAŞIM", None, "paylaşım, share"),
    ("facebook", "Facebook Grup Üye", "group", "GRUP ÜYE", None, "grup, üye, member"),
    ("facebook", "Facebook Reels İzlenme", "reels", "REELS İZLENME", None, "reels, izlenme, video"),
    ("facebook", "Facebook Canlı Yayın İzleyici", "live", "CANLI YAYIN", None, "canlı yayın, izleyici, live"),
]

SOCIAL, STREAM, MUSIC, AI = "SOSYAL MEDYA", "DİZİ & FİLM", "MÜZİK & VİDEO", "YAPAY ZEKÂ"
SOFT, SEC, GAME, GIFT, DATE = "YAZILIM", "GÜVENLİK", "OYUN", "HEDİYE KARTI", "ARKADAŞLIK"

# (urun adi, baslik, plan, alttaki buyuk yazi, kategori, simge, marka rengi, kelimeler)
CARDS = [
    ("Meta Verified Instagram 1 Aylık", "Meta Verified", "Instagram", "1 AYLIK", SOCIAL, "verified", (214, 41, 118), "meta verified, instagram, mavi tik, onaylı hesap, doğrulama"),
    ("Meta Verified Facebook 1 Aylık", "Meta Verified", "Facebook", "1 AYLIK", SOCIAL, "verified", (24, 119, 242), "meta verified, facebook, mavi tik, onaylı hesap, doğrulama"),
    ("X Premium 1 Aylık", "X Premium", "Mavi Tik", "1 AYLIK", SOCIAL, "verified", (34, 34, 40), "x premium, twitter, twitter blue, mavi tik, onaylı hesap"),
    ("X Premium+ 12 Aylık", "X Premium+", "Reklamsız", "12 AYLIK", SOCIAL, "verified", (34, 34, 40), "x premium plus, twitter, mavi tik, reklamsız, yıllık"),
    ("TikTok 700 Jeton", "TikTok", "Jeton", "700 JETON", SOCIAL, "coin", (254, 44, 85), "tiktok, jeton, coin, hediye, canlı yayın"),
    ("TikTok 1400 Jeton", "TikTok", "Jeton", "1400 JETON", SOCIAL, "coin", (254, 44, 85), "tiktok, jeton, coin, hediye, canlı yayın"),
    ("Snapchat+ 1 Aylık", "Snapchat+", "Abonelik", "1 AYLIK", SOCIAL, "crown", (255, 236, 0), "snapchat, snapchat plus, abonelik"),
    ("LinkedIn Premium Career 1 Aylık", "LinkedIn", "Premium Career", "1 AYLIK", SOCIAL, "crown", (10, 102, 194), "linkedin, premium, career, iş, kariyer"),
    ("Telegram Premium 1 Aylık", "Telegram", "Premium", "1 AYLIK", SOCIAL, "crown", (34, 158, 217), "telegram, premium"),
    ("Discord Nitro 1 Aylık", "Discord", "Nitro", "1 AYLIK", SOCIAL, "crown", (88, 101, 242), "discord, nitro"),
    ("Tinder Gold 1 Aylık", "Tinder", "Gold", "1 AYLIK", DATE, "heart", (253, 41, 123), "tinder, gold, arkadaşlık, flört"),
    ("Netflix Standart 1 Aylık", "Netflix", "Standart", "1 AYLIK", STREAM, "tv", (229, 9, 20), "netflix, dizi, film, standart"),
    ("Disney+ 1 Aylık", "Disney+", "Standart", "1 AYLIK", STREAM, "tv", (17, 60, 207), "disney, disney plus, dizi, film"),
    ("Amazon Prime 1 Aylık", "Amazon Prime", "Üyelik", "1 AYLIK", STREAM, "tv", (0, 168, 225), "amazon prime, prime video, dizi, film, kargo"),
    ("HBO Max 1 Aylık", "HBO Max", "Standart", "1 AYLIK", STREAM, "tv", (60, 80, 255), "hbo max, max, dizi, film"),
    ("Apple TV+ 1 Aylık", "Apple TV+", "Abonelik", "1 AYLIK", STREAM, "tv", (40, 40, 46), "apple tv, apple tv plus, dizi, film"),
    ("TOD 1 Aylık", "TOD", "Abonelik", "1 AYLIK", STREAM, "tv", (110, 40, 220), "tod, bein, maç, spor, futbol"),
    ("Spotify Premium Bireysel 1 Aylık", "Spotify", "Premium Bireysel", "1 AYLIK", MUSIC, "note", (29, 185, 84), "spotify, premium, bireysel, müzik"),
    ("YouTube Premium Bireysel 1 Aylık", "YouTube", "Premium Bireysel", "1 AYLIK", MUSIC, "play", (255, 30, 50), "youtube, premium, bireysel, reklamsız"),
    ("Deezer Premium 1 Aylık", "Deezer", "Premium", "1 AYLIK", MUSIC, "wave", (162, 56, 255), "deezer, premium, müzik"),
    ("ChatGPT Plus 1 Aylık", "ChatGPT", "Plus", "1 AYLIK", AI, "sparkle", (16, 163, 127), "chatgpt, openai, gpt, plus, yapay zeka"),
    ("Gemini Pro 12 Aylık", "Gemini", "Pro", "12 AYLIK", AI, "sparkle", (66, 133, 244), "gemini, google, google one, ai pro, yapay zeka, yıllık"),
    ("Claude Pro 1 Aylık", "Claude", "Pro", "1 AYLIK", AI, "sparkle", (217, 119, 87), "claude, anthropic, pro, yapay zeka"),
    ("Canva Pro 12 Aylık", "Canva", "Pro", "12 AYLIK", SOFT, "crown", (0, 170, 190), "canva, tasarım, pro, yıllık"),
    ("CapCut Pro 1 Aylık", "CapCut", "Pro", "1 AYLIK", SOFT, "play", (34, 34, 40), "capcut, video düzenleme, pro"),
    ("Zoom Pro 1 Aylık", "Zoom", "Pro", "1 AYLIK", SOFT, "video", (11, 92, 255), "zoom, toplantı, görüntülü görüşme, pro"),
    ("Windows 11 Pro Lisans", "Windows 11", "Pro", "LİSANS", SOFT, "key", (0, 120, 212), "windows 11, windows, lisans, key, anahtar"),
    ("Office 2024 Pro Plus Lisans", "Office 2024", "Pro Plus", "LİSANS", SOFT, "key", (235, 60, 0), "office 2024, office, word, excel, lisans, key"),
    ("Kaspersky Premium 1 Yıllık", "Kaspersky", "Premium", "1 YILLIK", SEC, "shield", (0, 168, 142), "kaspersky, antivirüs, virüs programı, güvenlik"),
    ("ESET Internet Security 1 Yıllık", "ESET", "Internet Security", "1 YILLIK", SEC, "shield", (0, 150, 160), "eset, nod32, antivirüs, virüs programı, güvenlik"),
    ("Google Play Hediye Kartı 100 TL", "Google Play", "Hediye Kartı", "100 TL", GIFT, "play", (52, 168, 83), "google play, hediye kartı, gift card, android, bakiye"),
    ("App Store Hediye Kartı 100 TL", "App Store", "Hediye Kartı", "100 TL", GIFT, "gift", (10, 132, 255), "app store, itunes, apple, hediye kartı, gift card, bakiye"),
    ("Steam Cüzdan Kodu 250 TL", "Steam", "Cüzdan Kodu", "250 TL", GAME, "card", (27, 40, 56), "steam, cüzdan, wallet, oyun, e-pin"),
    ("PlayStation Store Cüzdan Kodu 250 TL", "PlayStation", "Store Cüzdan Kodu", "250 TL", GAME, "gamepad", (0, 67, 156), "playstation, psn, ps store, cüzdan, oyun, e-pin"),
    ("Razer Gold 100 TL", "Razer Gold", "E-Pin", "100 TL", GAME, "coin", (68, 214, 44), "razer gold, e-pin, oyun, bakiye"),
    ("PUBG Mobile 325 UC", "PUBG Mobile", "E-Pin", "325 UC", GAME, "coin", (242, 169, 0), "pubg, uc, pubg mobile, e-pin, oyun"),
    ("Valorant 475 VP", "Valorant", "E-Pin", "475 VP", GAME, "coin", (255, 70, 85), "valorant, vp, valorant point, e-pin, oyun"),
    ("Free Fire 520 Elmas", "Free Fire", "E-Pin", "520 ELMAS", GAME, "gem", (255, 120, 0), "free fire, elmas, e-pin, oyun"),
    ("Roblox 400 Robux", "Roblox", "E-Pin", "400 ROBUX", GAME, "coin", (70, 75, 90), "roblox, robux, e-pin, oyun"),
]


# ---------------------------------------------------------------------------
# Yardimcilar
# ---------------------------------------------------------------------------


def mix(a, b, t):
    return tuple(round(a[k] + (b[k] - a[k]) * t) for k in range(3))


def is_light(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2] > 175


def rgba(img, c, a=255):
    return c + (a,) if img.mode == "RGBA" else c


def icon_mask(kind, cx, cy, u):
    """Ilk turun simgeleri + bu turun yenileri (onay rozeti, hediye, kamera)."""
    if kind not in ("verified", "gift", "video"):
        return base.icon_mask(kind, cx, cy, u)
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    if kind == "verified":
        pts = []
        for i in range(400):
            t = 2 * math.pi * i / 400
            r = u * 0.5 * (1 + 0.075 * math.cos(8 * t))
            pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
        d.polygon(pts, fill=255)
        d.line([(cx - u * 0.21, cy + u * 0.01), (cx - u * 0.05, cy + u * 0.17), (cx + u * 0.23, cy - u * 0.14)],
               fill=0, width=int(u * 0.11), joint="curve")
    elif kind == "gift":
        d.rounded_rectangle((cx - u * 0.42, cy - u * 0.02, cx + u * 0.42, cy + u * 0.52), radius=u * 0.05, fill=255)
        d.rounded_rectangle((cx - u * 0.5, cy - u * 0.26, cx + u * 0.5, cy - u * 0.07), radius=u * 0.05, fill=255)
        d.rectangle((cx - u * 0.05, cy - u * 0.26, cx + u * 0.05, cy + u * 0.52), fill=0)
        for sx in (-1, 1):
            box = sorted((cx + sx * u * 0.04, cx + sx * u * 0.36))
            d.ellipse((box[0], cy - u * 0.56, box[1], cy - u * 0.3), fill=255)
            hole = sorted((cx + sx * u * 0.12, cx + sx * u * 0.27))
            d.ellipse((hole[0], cy - u * 0.48, hole[1], cy - u * 0.38), fill=0)
    else:  # video kamera
        d.rounded_rectangle((cx - u * 0.52, cy - u * 0.3, cx + u * 0.16, cy + u * 0.3), radius=u * 0.1, fill=255)
        d.polygon([(cx + u * 0.22, cy - u * 0.05), (cx + u * 0.52, cy - u * 0.27),
                   (cx + u * 0.52, cy + u * 0.27), (cx + u * 0.22, cy + u * 0.05)], fill=255)
    return m


def paint_icon(img, mask, platform, fill=WHITE, off=14):
    if P2[platform]["glitch"]:
        img.paste(rgba(img, TT_CYAN), (0, 0), ImageChops.offset(mask, -off, -off))
        img.paste(rgba(img, TT_RED), (0, 0), ImageChops.offset(mask, off, off))
    img.paste(rgba(img, fill), (0, 0), mask)


def paint_accent(img, mask, platform):
    """Platformun vurgu rengi; Instagram'da degrade."""
    acc = P2[platform]["accent"]
    if acc == "gradient":
        img.paste(diagonal_gradient(IG_STOPS), (0, 0), mask)
    else:
        img.paste(rgba(img, acc), (0, 0), mask)


def text_left(d, x, cy, text, f, fill):
    box = d.textbbox((0, 0), text, font=f)
    d.text((x - box[0], cy - (box[3] - box[1]) / 2 - box[1]), text, font=f, fill=fill)


def text_center(d, cy, text, f, fill):
    box = d.textbbox((0, 0), text, font=f)
    d.text(((S - (box[2] - box[0])) / 2 - box[0], cy - (box[3] - box[1]) / 2 - box[1]), text, font=f, fill=fill)


def drop_shadow(img, alpha, color, dx, dy, blur, strength):
    sh = alpha.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * strength))
    moved = Image.new("L", (S, S), 0)  # ImageChops.offset sarar: alttaki golge uste cikar
    moved.paste(sh, (dx, dy))
    img.paste(color, (0, 0), moved)


def light_bg(tint, tint2=None):
    """Acik zemin: ustte hafif renkli, kosede yumusak renk lekeleri, ince nokta deseni."""
    top = mix(tint, WHITE, 0.9)
    g = Image.linear_gradient("L").resize((S, S))
    img = Image.composite(Image.new("RGB", (S, S), (250, 250, 252)), Image.new("RGB", (S, S), top), g)
    blob = Image.new("L", (S, S), 0)
    ImageDraw.Draw(blob).ellipse((1150, -350, 2450, 950), fill=255)
    img.paste(tint, (0, 0), blob.filter(ImageFilter.GaussianBlur(280)).point(lambda v: int(v * 0.22)))
    blob = Image.new("L", (S, S), 0)
    ImageDraw.Draw(blob).ellipse((-450, 1150, 850, 2450), fill=255)
    img.paste(tint2 or tint, (0, 0), blob.filter(ImageFilter.GaussianBlur(280)).point(lambda v: int(v * 0.14)))
    dots = Image.new("L", (S, S), 0)
    dd = ImageDraw.Draw(dots)
    for y in range(40, S, 80):
        for x in range(40, S, 80):
            dd.ellipse((x - 4, y - 4, x + 4, y + 4), fill=22)
    img.paste(INK, (0, 0), dots)
    return img


# ---------------------------------------------------------------------------
# Tasarim 6: telefon + bildirim karti
# ---------------------------------------------------------------------------

GRID_LIGHT = [(255, 205, 178), (181, 222, 255), (255, 228, 160), (200, 236, 210), (226, 206, 255),
              (255, 196, 214), (190, 230, 240), (255, 215, 190), (215, 225, 255)]
GRID_DARK = [(60, 44, 70), (34, 56, 80), (70, 52, 36), (36, 66, 52), (58, 40, 62), (76, 38, 48),
             (32, 60, 66), (66, 50, 40), (44, 48, 78)]


def phone_layer(platform):
    p = P2[platform]
    dark = platform in ("tiktok", "x")
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = 470, 430, 1250, 2120
    d.rounded_rectangle((x0, y0, x1, y1), radius=130, fill=(22, 22, 26, 255), outline=(96, 96, 106, 255), width=8)
    sx0, sy0, sx1, sy1 = x0 + 34, y0 + 34, x1 - 34, y1 - 34
    screen_bg = (14, 14, 18) if dark else WHITE
    d.rounded_rectangle((sx0, sy0, sx1, sy1), radius=100, fill=screen_bg + (255,))
    cx = (x0 + x1) / 2
    d.rounded_rectangle((cx - 110, y0 + 66, cx + 110, y0 + 126), radius=30, fill=(0, 0, 0, 255))

    bar = (70, 72, 82, 255) if dark else (214, 217, 224, 255)
    bar2 = (48, 50, 58, 255) if dark else (232, 234, 239, 255)
    num = (200, 202, 210, 255) if dark else (60, 62, 72, 255)
    left, top = sx0 + 60, y0 + 190
    d.rounded_rectangle((left, top, left + 280, top + 44), radius=22, fill=num)

    ax, ay, ar = left + 105, top + 250, 105
    ring = Image.new("L", (S, S), 0)
    ImageDraw.Draw(ring).ellipse((ax - ar - 20, ay - ar - 20, ax + ar + 20, ay + ar + 20), fill=255)
    ImageDraw.Draw(ring).ellipse((ax - ar - 6, ay - ar - 6, ax + ar + 6, ay + ar + 6), fill=0)
    ring_color = {"x": (140, 146, 156), "tiktok": (254, 44, 85)}.get(platform)
    if ring_color:
        layer.paste(ring_color + (255,), (0, 0), ring)
    else:
        paint_accent(layer, ring, platform)
    av = Image.new("L", (S, S), 0)
    ImageDraw.Draw(av).ellipse((ax - ar, ay - ar, ax + ar, ay + ar), fill=255)
    layer.paste((96, 100, 112, 255) if dark else (205, 209, 218, 255), (0, 0), av)
    person = Image.new("L", (S, S), 0)
    pd = ImageDraw.Draw(person)
    pd.ellipse((ax - 40, ay - 62, ax + 40, ay + 18), fill=255)
    pd.ellipse((ax - 80, ay + 34, ax + 80, ay + 190), fill=255)
    layer.paste((150, 154, 166, 255) if dark else (240, 242, 246, 255), (0, 0), ImageChops.multiply(person, av))

    for k in range(3):
        x = left + 290 + k * 135
        d.rounded_rectangle((x, ay - 46, x + 92, ay - 6), radius=14, fill=num)
        d.rounded_rectangle((x - 6, ay + 22, x + 104, ay + 46), radius=12, fill=bar)
    d.rounded_rectangle((left, ay + 150, left + 360, ay + 182), radius=16, fill=bar)
    d.rounded_rectangle((left, ay + 206, left + 520, ay + 236), radius=15, fill=bar2)
    by = ay + 280
    d.rounded_rectangle((left, by, sx1 - 60, by + 84), radius=22, fill=p["button"] + (255,))

    gy = by + 130
    gap = 12
    cell = (sx1 - sx0 - 2 * gap) / 3
    palette = GRID_DARK if dark else GRID_LIGHT
    for i in range(12):
        r, c = divmod(i, 3)
        bx = sx0 + c * (cell + gap)
        byy = gy + r * (cell + gap)
        tile = diagonal_gradient([(0, palette[i % 9]), (1, mix(palette[i % 9], WHITE if not dark else (0, 0, 0), 0.35))],
                                 size=int(cell))
        m = Image.new("L", tile.size, 255)
        layer.paste(tile, (int(bx), int(byy)), m)
    # ekran disina tasan izgarayi ekran bicimiyle kirp
    screen_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(screen_mask).rounded_rectangle((sx0, sy0, sx1, sy1), radius=100, fill=255)
    body = Image.new("L", (S, S), 0)
    ImageDraw.Draw(body).rounded_rectangle((x0, y0, x1, y1), radius=130, fill=255)
    frame = ImageChops.subtract(body, screen_mask)
    framed = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    framed.paste(layer, (0, 0), body)
    framed.paste((22, 22, 26, 255), (0, 0), frame)
    ImageDraw.Draw(framed).rounded_rectangle((x0, y0, x1, y1), radius=130, outline=(96, 96, 106, 255), width=8)
    ImageDraw.Draw(framed).rounded_rectangle((cx - 110, y0 + 66, cx + 110, y0 + 126), radius=30, fill=(0, 0, 0, 255))
    return framed.rotate(6, resample=Image.BICUBIC, center=(860, 1275))


def render_phone(platform, icon, label, badge):
    cfg = PLATFORMS[platform]
    img = base.background(cfg["bg"])
    base.draw_platform_pill(img, cfg["label"], cfg["bg"][0] == "glow")

    phone = phone_layer(platform)
    drop_shadow(img, phone.split()[3], (0, 0, 0), 40, 60, 50, 0.55)
    img.paste(phone, (0, 0), phone)

    # Kucuk bildirim balonu (telefonun sag ust kosesi)
    bx, by, bw, bh = 1110, 520, 400, 170
    bub = Image.new("L", (S, S), 0)
    bd = ImageDraw.Draw(bub)
    bd.rounded_rectangle((bx, by, bx + bw, by + bh), radius=bh / 2, fill=255)
    bd.polygon([(bx + 70, by + bh - 10), (bx + 40, by + bh + 60), (bx + 140, by + bh - 10)], fill=255)
    drop_shadow(img, bub, (0, 0, 0), 0, 24, 26, 0.45)
    img.paste((255, 48, 64), (0, 0), bub)
    img.paste(WHITE, (0, 0), icon_mask(icon, bx + 100, by + bh / 2, 110))
    d = ImageDraw.Draw(img)
    text_left(d, bx + 205, by + bh / 2, "99+", font(FONT_BLACK, 96), WHITE)

    # Yuzen bildirim karti
    card = (720, 1180, 1900, 1610)
    cm = Image.new("L", (S, S), 0)
    ImageDraw.Draw(cm).rounded_rectangle(card, radius=90, fill=255)
    drop_shadow(img, cm, (0, 0, 0), 0, 40, 50, 0.5)
    img.paste(WHITE, (0, 0), cm)
    icx, icy, ir = card[0] + 210, (card[1] + card[3]) / 2, 150
    circ = Image.new("L", (S, S), 0)
    ImageDraw.Draw(circ).ellipse((icx - ir, icy - ir, icx + ir, icy + ir), fill=255)
    paint_accent(img, circ, platform)
    paint_icon(img, icon_mask(icon, icx, icy, 190), platform, off=7)
    tx = icx + ir + 60
    max_w = card[2] - 70 - tx
    d = ImageDraw.Draw(img)
    f_label = fit_font(label, FONT_BLACK, max_w, 160)
    text_left(d, tx, icy - 62, label, f_label, INK)
    # yesil yukari ok + platform adi
    ay = icy + 92
    d.polygon([(tx, ay + 28), (tx + 30, ay - 26), (tx + 60, ay + 28)], fill=(34, 197, 94))
    text_left(d, tx + 90, ay, cfg["label"], fit_font(cfg["label"], FONT_BOLD, max_w - 90, 96), (110, 114, 126))

    if badge:
        base.draw_badge(img, badge, 1760)
    return img.resize((FINAL, FINAL), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Tasarim 7: 3D karo
# ---------------------------------------------------------------------------


def render_sticker(platform, icon, label, badge):
    p = P2[platform]
    img = light_bg(p["tint"], p["tint2"])
    d = ImageDraw.Draw(img)
    name = PLATFORMS[platform]["label"]
    text_center(d, 230, name, fit_font(name, FONT_BLACK, S - 400, 140), p["ink"])

    cx, cy, T = 1000, 900, 860
    box = (cx - T / 2, cy - T / 2, cx + T / 2, cy + T / 2)
    tmask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(tmask).rounded_rectangle(box, radius=230, fill=255)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.paste(diagonal_gradient(p["tile"]), (0, 0), tmask)
    gloss = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gloss).ellipse((box[0] - 300, box[1] - 520, box[2] + 60, box[1] + 400), fill=62)
    layer.paste((255, 255, 255, 255), (0, 0), ImageChops.multiply(gloss, tmask))
    rim = Image.new("L", (S, S), 0)
    ImageDraw.Draw(rim).rounded_rectangle((box[0] + 8, box[1] + 8, box[2] - 8, box[3] - 8), radius=222,
                                          outline=80, width=10)
    layer.paste((255, 255, 255, 255), (0, 0), rim)
    paint_icon(layer, icon_mask(icon, cx, cy, 520), platform, off=14)
    layer = layer.rotate(7, resample=Image.BICUBIC, center=(cx, cy))

    shadow_color = shade(p["tint"], 0.55) if platform != "x" else (40, 44, 52)
    drop_shadow(img, layer.split()[3], shadow_color, 0, 90, 80, 0.55)
    img.paste(layer, (0, 0), layer)

    # Susleme: kucuk arti isaretleri ve noktalar
    d = ImageDraw.Draw(img)
    for (x, y, r), c in zip(((300, 560, 34), (1730, 1300, 28), (1690, 470, 18), (330, 1290, 16)),
                            (p["tint"], p["tint2"], p["tint2"], p["tint"])):
        if r > 20:
            d.rounded_rectangle((x - r, y - r * 0.3, x + r, y + r * 0.3), radius=r * 0.3, fill=c)
            d.rounded_rectangle((x - r * 0.3, y - r, x + r * 0.3, y + r), radius=r * 0.3, fill=c)
        else:
            d.ellipse((x - r, y - r, x + r, y + r), fill=c)

    if badge:
        base.draw_badge(img, badge, 1540)
        label_cy = 1770
    else:
        label_cy = 1650
    text_center(ImageDraw.Draw(img), label_cy, label, fit_font(label, FONT_BLACK, S - 260, 250), INK)
    return img.resize((FINAL, FINAL), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Tasarim 8: hediye karti
# ---------------------------------------------------------------------------


def spaced(d, x, cy, text, f, fill, gap=12):
    box = d.textbbox((0, 0), text, font=f)
    y = cy - (box[3] - box[1]) / 2 - box[1]
    for ch in text:
        d.text((x, y), ch, font=f, fill=fill)
        x += d.textlength(ch, font=f) + gap


def card_layer(color, cx, cy, w, h, angle, title=None, plan=None, category=None, icon=None):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    box = (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
    cm = Image.new("L", (S, S), 0)
    ImageDraw.Draw(cm).rounded_rectangle(box, radius=72, fill=255)
    light = mix(color, WHITE, 0.28)
    layer.paste(diagonal_gradient([(0, shade(color, 0.55)), (0.55, color), (1, light)]), (0, 0), cm)
    if title is None:  # arkadaki sade kart
        return layer.rotate(angle, resample=Image.BICUBIC, center=(cx, cy))

    rings = Image.new("L", (S, S), 0)
    rd = ImageDraw.Draw(rings)
    ox, oy = box[2] - 120, box[3] - 60
    for r in range(260, 1100, 130):
        rd.ellipse((ox - r, oy - r, ox + r, oy + r), outline=30, width=12)
    layer.paste((255, 255, 255, 255), (0, 0), ImageChops.multiply(rings, cm))
    wm = icon_mask(icon, box[2] - 330, box[1] + 330, 560).point(lambda v: int(v * 0.2))
    layer.paste((255, 255, 255, 255), (0, 0), ImageChops.multiply(wm, cm))

    dark_text = is_light(color)
    tc = INK + (255,) if dark_text else (255, 255, 255, 255)
    sub = INK + (190,) if dark_text else (255, 255, 255, 215)
    d = ImageDraw.Draw(layer)
    left = box[0] + 120
    text_left(d, left, box[1] + 190, title, fit_font(title, FONT_BLACK, w - 600, 190), tc)
    text_left(d, left, box[1] + 350, plan, fit_font(plan, FONT_BOLD, w - 600, 120), sub)

    chip = (left, box[1] + 480, left + 210, box[1] + 640)
    chm = Image.new("L", (S, S), 0)
    ImageDraw.Draw(chm).rounded_rectangle(chip, radius=34, fill=255)
    layer.paste(diagonal_gradient([(0, (196, 150, 64)), (1, (246, 214, 132))]), (0, 0), chm)
    line = (150, 110, 40, 255)
    d.line([(chip[0], chip[1] + 55), (chip[2], chip[1] + 55)], fill=line, width=6)
    d.line([(chip[0], chip[3] - 55), (chip[2], chip[3] - 55)], fill=line, width=6)
    d.line([((chip[0] + chip[2]) / 2, chip[1] + 55), ((chip[0] + chip[2]) / 2, chip[3] - 55)], fill=line, width=6)
    wx, wy = chip[2] + 70, (chip[1] + chip[3]) / 2
    for r in (34, 66, 98):
        d.arc((wx - r, wy - r, wx + r, wy + r), -50, 50, fill=tc, width=12)

    spaced(d, left, box[3] - 110, category, font(FONT_BOLD, 64), sub, gap=10)
    return layer.rotate(angle, resample=Image.BICUBIC, center=(cx, cy))


def render_card(title, plan, big, category, icon, color):
    img = light_bg(color)
    cx, cy, w, h = 1000, 790, 1540, 970

    back = card_layer(mix(color, WHITE, 0.55), cx + 60, cy + 30, w, h, -5)
    drop_shadow(img, back.split()[3], shade(color, 0.5), 0, 40, 50, 0.25)
    img.paste(back, (0, 0), back)

    front = card_layer(color, cx, cy, w, h, 7, title, plan, category, icon)
    drop_shadow(img, front.split()[3], shade(color, 0.4), 0, 70, 60, 0.5)
    img.paste(front, (0, 0), front)

    d = ImageDraw.Draw(img)
    text_center(d, 1660, big, fit_font(big, FONT_BLACK, S - 300, 270), INK)
    accent = color if not is_light(color) else shade(color, 0.75)
    d.rounded_rectangle((S / 2 - 120, 1830, S / 2 + 120, 1848), radius=9, fill=accent)
    return img.resize((FINAL, FINAL), Image.LANCZOS)


# ---------------------------------------------------------------------------


def main():
    for p in (FONT_BLACK, FONT_BOLD):
        if not os.path.exists(p):
            sys.exit(f"Yazı tipi yok: {p}")
    out_dir = os.path.join(OUT, FOLDER)
    os.makedirs(out_dir, exist_ok=True)
    sheets = {"telefon": [], "3d": [], "kart": []}
    with open(os.path.join(OUT, "kelimeler.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["dosya", "ad", "kelimeler"])

        def save(sheet, suffix, name, img, words):
            file_name = f"{name} - {suffix}"
            img.save(os.path.join(out_dir, file_name + ".png"), optimize=True)
            w.writerow([f"{FOLDER}/{file_name}.png", name, words])
            sheets[sheet].append(img.resize((250, 250), Image.LANCZOS))
            print(file_name)

        for platform, name, icon, label, badge, words in PHONE:
            save("telefon", "Telefon", name, render_phone(platform, icon, label, badge),
                 f"{PLATFORMS[platform]['words']}, {words}, dijital")
        for platform, name, icon, label, badge, words in STICKER:
            save("3d", "3D", name, render_sticker(platform, icon, label, badge),
                 f"{PLATFORMS[platform]['words']}, {words}, dijital")
        for name, title, plan, big, category, icon, color, words in CARDS:
            save("kart", "Kart", name, render_card(title, plan, big, category, icon, color),
                 f"{words}, {tr_lower(category)}, {tr_lower(big)}, dijital")

    for key, thumbs in sheets.items():
        cols = 8
        rows = -(-len(thumbs) // cols)
        sheet = Image.new("RGB", (cols * 260 + 10, rows * 260 + 10), (240, 240, 240))
        for i, t in enumerate(thumbs):
            sheet.paste(t, (10 + (i % cols) * 260, 10 + (i // cols) * 260))
        sheet.save(os.path.join(OUT, f"ornekler_{key}.png"))
    print(f"{sum(len(t) for t in sheets.values())} görsel -> {out_dir}")


if __name__ == "__main__":
    main()
