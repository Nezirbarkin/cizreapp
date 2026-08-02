#!/usr/bin/env python3
"""
Sadece ana dosyadan metotları sil. Part dosyalarına yazma.
"""

import json

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"
BOUNDS = r"C:\Users\lenovo\cizreapp\scripts\_method_bounds.json"

# Ana dosyada kalması gereken metotlar (bounds.json'da OLMAYAN)
KEEP = {"_setupRealtimeSubscription", "_loadRealData", "_buildBody", "build",
        "_buildComingSoon", "_buildInfoRow"}


def main():
    with open(SRC, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    with open(BOUNDS, 'r') as f:
        methods = json.load(f)

    # Sadece bounds'taki metotları al, KEEP'te olanları atla
    to_remove = []
    for name, info in methods.items():
        if name in KEEP:
            continue
        to_remove.append(tuple(info["bounds"]))

    print(f"Toplam: {len(to_remove)} metot silinecek")

    # Sondan başa doğru sil
    to_remove.sort(key=lambda x: -x[0])
    new_lines = lines[:]
    for start, end in to_remove:
        if end >= len(new_lines):
            print(f"  UYARI: {start}-{end} sinir asildi, atlaniyor")
            continue
        # Önceki boş satırı da sil
        delete_start = start
        if start > 0 and new_lines[start-1].strip() == "":
            delete_start = start - 1
        del new_lines[delete_start:end+1]

    with open(SRC, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    print(f"Ana dosya: {len(lines)} -> {len(new_lines)} satir")


if __name__ == "__main__":
    main()
