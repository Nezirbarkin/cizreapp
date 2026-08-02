#!/usr/bin/env python3
"""Ana dosyada 192-2005 arasindaki orphan kodlari temizle, sadece build() ve class } kalsin."""

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"

with open(SRC, 'r', encoding='utf-8') as f:
    lines = f.read().split('\n')

# 192. satir (0-indexed 191) build()'in son '}'i
# 2006. satir (0-indexed 2005) class '}'
# Aradaki 193-2005 (0-indexed 192-2004) orphan

# Guvenli: once 2005-193 arasinda gercek metot var mi kontrol et
between = lines[192:2005]  # 193-2005 arasi (1-indexed)
# Metot tanimi var mi? (2 boslukla baslayan ve _ ile baslayan identifier)
import re
real_methods = []
for idx, line in enumerate(between, start=193):
    if re.match(r'^  [A-Za-z]+(<[^>]+>)?\s+_[a-zA-Z_]+\s*\(', line):
        real_methods.append((idx, line.strip()))

print(f"193-2005 arasi {len(real_methods)} gercek metot tanimi var:")
for ln, code in real_methods:
    print(f"  satir {ln}: {code}")

# Eger gercek metot yoksa, 193-2005 arasini sil
if not real_methods:
    # lines[192] = satir 193
    new_lines = lines[:192] + ['}'] + lines[2005:]
    with open(SRC, 'w', encoding='utf-8') as f:
        f.write('\n'.join(new_lines))
    print(f"\nOrphan blok silindi (193-2005)")
    print(f"Yeni satir sayisi: {len(new_lines)}")
else:
    print("\nGercek metotlar var, dikkatli ol!")
