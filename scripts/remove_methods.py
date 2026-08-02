#!/usr/bin/env python3
"""
Tüm metotları ana dosyadan çıkar ve part dosyalarına yaz.
"""

import os
import json
from collections import defaultdict

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"
BOUNDS = r"C:\Users\lenovo\cizreapp\scripts\_method_bounds.json"
PARTS_DIR = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_parts"

PART_TO_FILE = {
    "drawer": "_part_drawer.dart",
    "dashboard": "_part_dashboard.dart",
    "users": "_part_users.dart",
    "posts": "_part_posts.dart",
    "products": "_part_products.dart",
    "categories": "_part_categories.dart",
    "shops": "_part_shops.dart",
    "orders": "_part_orders.dart",
    "reports": "_part_reports.dart",
    "post_reports": "_part_post_reports.dart",
    "support_tickets": "_part_support_tickets.dart",
    "payments": "_part_payments.dart",
    "reports_page": "_part_reports_page.dart",
    "analytics": "_part_analytics.dart",
    "logs": "_part_logs.dart",
    "settings": "_part_settings.dart",
    "api_settings": "_part_api_settings.dart",
    "courier": "_part_courier.dart",
}

PART_DESC = {
    "drawer": "Drawer widgets (menu)",
    "dashboard": "Dashboard ana sayfa + istatistik kartlari",
    "users": "Kullanicilar sekmesi + dialoglar",
    "posts": "Gonderiler + hikayeler + dialoglar",
    "products": "Urunler + ekleme/duzenleme/silme dialoglari",
    "categories": "Kategoriler + ekleme/duzenleme/silme dialoglari",
    "shops": "Dukkanlar + kart + ekleme/duzenleme/silme dialoglari",
    "orders": "Siparisler + kart + durum dialoglari",
    "reports": "Sikayetler + rapor kartlari + detay/silme",
    "post_reports": "Gonderi sikayetleri + detay/silme",
    "support_tickets": "Destek talepleri + detay dialog",
    "payments": "Odemeler + payout islemleri + dialoglar",
    "reports_page": "Raporlar sayfasi + grafik olusturucular",
    "analytics": "Analitik icerigi",
    "logs": "Loglar",
    "settings": "Ayarlar + siparis kontrol + duyuru",
    "api_settings": "API ayarlari + Iyzico + S3 + API key + webhooks",
    "courier": "Kurye yonetimi + bakiye/odeme dialoglari",
}


def main():
    with open(SRC, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    with open(BOUNDS, 'r') as f:
        methods = json.load(f)

    # Tüm metotları part'lara ata
    part_methods = defaultdict(list)
    for name, info in methods.items():
        part_methods[info["part"]].append((name, info["bounds"][0], info["bounds"][1]))

    # 1) Part dosyalarını yaz
    os.makedirs(PARTS_DIR, exist_ok=True)
    # Mevcut part dosyalarını temizle (helpers ve drawer'ı koru)
    preserve = {"_part_helpers.dart", "_part_drawer.dart"}
    for fn in os.listdir(PARTS_DIR):
        if fn.endswith(".dart") and fn not in preserve:
            os.remove(os.path.join(PARTS_DIR, fn))

    for part_key, method_list in part_methods.items():
        filename = PART_TO_FILE.get(part_key)
        if not filename:
            print(f"  PART DOSYASI YOK: {part_key}")
            continue
        method_list.sort(key=lambda x: x[1])
        content_parts = [f"part of '../admin_dashboard_screen.dart';\n\n"]
        content_parts.append(f"// {'='*74}\n")
        content_parts.append(f"// {PART_DESC.get(part_key, part_key)}\n")
        content_parts.append(f"// {'='*74}\n\n")
        for method_name, start, end in method_list:
            content_parts.append(f"// --- {method_name} ---\n")
            content_parts.extend(lines[start:end+1])
            content_parts.append("\n\n")
        filepath = os.path.join(PARTS_DIR, filename)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(content_parts)
        total_lines = sum(end - start + 1 for _, start, end in method_list)
        print(f"  {filename}: {len(method_list)} metot, {total_lines} satir")

    # 2) Ana dosyadan metotları sil
    # Bounds listesini sondan başa doğru sil (satır numaraları kaymasın)
    all_bounds = sorted([(b[0], b[1]) for info in methods.values() for b in [info["bounds"]]], key=lambda x: -x[0])
    # Her aralığı sil ve aralıktan hemen önceki boş satırı da sil
    new_lines = lines[:]
    for start, end in all_bounds:
        # start'tan end'e kadar dahil
        # Önceki satır boşsa onu da sil (aralıklar arası temiz olsun)
        delete_start = start
        if start > 0 and new_lines[start-1].strip() == "":
            delete_start = start - 1
        del new_lines[delete_start:end+1]

    with open(SRC, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    print(f"\nAna dosya: {len(lines)} -> {len(new_lines)} satir")


if __name__ == "__main__":
    main()
