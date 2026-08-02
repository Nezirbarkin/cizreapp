#!/usr/bin/env python3
"""Ana dosyadan orphan kod bloklarını temizle."""

import re

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"


def main():
    with open(SRC, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    # Class içindeki metod tanımlarını bul
    # Bir metot tanımı: 2 boşluk + return type + ad + (
    method_start_pattern = re.compile(
        r'^  (?:static\s+)?(?:Widget|Future<[^>]*>|void|bool|int|double|String|List<[^>]*>|Map<[^>]*>)\s+[a-zA-Z_][a-zA-Z0-9_]*\s*\('
    )

    # Orphan olabilecek satırları bul
    # Bunlar: 2-boşluk indentli, metot tanımı olmayan, ve öncesinde } olan
    # (yani bir önceki metot bittikten sonra orphan başlamış)

    orphan_ranges = []
    i = 0
    in_class = False
    while i < len(lines):
        line = lines[i]
        if not in_class:
            if 'class AdminDashboardScreen extends' in line or 'class _AdminDashboardScreenState extends' in line:
                in_class = True
            i += 1
            continue

        # Method tanımı mı?
        if method_start_pattern.match(line.lstrip()) and (line.startswith('  ') and not line.startswith('   ')):
            # Method bulundu, atla
            i += 1
            continue

        # Method tanımı değil ama 2-boşluk indentli
        if line.startswith('  ') and not line.startswith('   ') and line.strip():
            # Boş olmayan satır
            stripped = line.lstrip()
            # State field'ı olabilir (final, int, String, bool, var)
            if any(stripped.startswith(kw) for kw in ['final ', 'int ', 'String ', 'bool ', 'double ', 'var ', 'Future<', 'List<', 'Map<', 'RealtimeChannel', 'const ', 'TextEditingController', 'CancellationRequestService']):
                i += 1
                continue
            # @override olabilir
            if stripped.startswith('@override'):
                i += 1
                continue
            # super.key, createState vs.
            if 'super.key' in line or 'createState' in line or '=>' in line:
                i += 1
                continue
            # Bu orphan olabilir
            # Önceki satır } ise veya boşsa, bu orphan
            prev = lines[i-1] if i > 0 else ""
            if prev.strip() == "}" or prev.strip() == "":
                # Orphan başlangıcı
                start = i
                # Brace eşleştirme ile sonu bul
                # Bu satırla başlayan blok orphan
                # Önceki non-whitespace satıra kadar devam et
                # Basit yaklaşım: sonraki method tanımına kadar
                j = i + 1
                brace_count = line.count('{') - line.count('}')
                while j < len(lines):
                    if method_start_pattern.match(lines[j].lstrip()) and lines[j].startswith('  ') and not lines[j].startswith('   '):
                        # Yeni method bulundu
                        break
                    brace_count += lines[j].count('{') - lines[j].count('}')
                    j += 1
                end = j
                # Son satırı atla (boş satır)
                if end > start and lines[end-1].strip() == "":
                    end -= 1
                orphan_ranges.append((start, end, line.rstrip()[:60]))
                i = end
                continue
        i += 1

    print(f"Orphan bloklar bulundu: {len(orphan_ranges)}")
    for s, e, txt in orphan_ranges[:20]:
        print(f"  satir {s+1}-{e}: {txt}")

    # Sondan başa doğru sil
    orphan_ranges.sort(key=lambda x: -x[0])
    for s, e, _ in orphan_ranges:
        del lines[s:e]


if __name__ == "__main__":
    main()
