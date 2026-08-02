#!/usr/bin/env python3
"""Ana dosyada part dosyalarına taşınmış metotların orphan gövdelerini temizle."""

import os
import re

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"
PARTS_DIR = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_parts"


def collect_part_bodies():
    """Her part dosyasından metot gövdelerini (ilk birkaç satır) topla."""
    bodies = []
    for fn in os.listdir(PARTS_DIR):
        if not fn.endswith('.dart'):
            continue
        with open(os.path.join(PARTS_DIR, fn), 'r', encoding='utf-8') as f:
            text = f.read()
        # Her `// --- _name ---` bloğu için, method_name ve ilk birkaç gövde satırı
        for m in re.finditer(
            r'// --- (_[a-zA-Z_][a-zA-Z0-9_]*) ---\s*\n[^\n]+\s*\([^)]*\)[^{]*\{[^{}\n]*\n((?:[ \t]+[^\n]+\n){1,3})',
            text
        ):
            bodies.append({
                'name': m.group(1),
                'first_lines': [l.strip() for l in m.group(2).splitlines() if l.strip()],
            })
    return bodies


def main():
    bodies = collect_part_bodies()
    print(f"Part dosyalarinda {len(bodies)} metot govdesi bulundu")

    with open(SRC, 'r', encoding='utf-8') as f:
        content = f.read()
    lines = content.split('\n')

    # Her orphan aday bloğu için: ilk 3 satırdan birinin part dosyalarında olup olmadığına bak
    # Aslında daha kolay: part dosyalarına taşınmış ama ana dosyada kalmış gövdeleri bul
    # Bu gövdeler `) {` ile başlıyor (orphan signature) ya da direkt `// --- _name ---` ile

    silinen = 0
    yeni_lines = []
    i = 0
    while i < len(lines):
        line = lines[i]
        # Orphan imza pattern'i: `) {` veya ` {` ile başlayan ve öncesinde metot tanımı olmayan
        # ya da `// --- _name ---` yorumu
        if re.match(r'^\s*\)\s*\{\s*$', line) or re.match(r'^\s*// --- (_[a-zA-Z_]+) ---\s*$', line):
            # Bu bir orphan bloğu olabilir
            # Brace matching ile bloğun sonunu bul
            j = i
            depth = 0
            started = False
            while j < len(lines):
                for ch in lines[j]:
                    if ch == '{':
                        depth += 1
                        started = True
                    elif ch == '}':
                        depth -= 1
                if started and depth <= 0:
                    # Bloğun sonu j. satır
                    # Önceki boş satırları da sil
                    while yeni_lines and yeni_lines[-1].strip() == '':
                        yeni_lines.pop()
                    # Bir önceki gerçek satır da yorum ise sil
                    while yeni_lines and yeni_lines[-1].strip().startswith('//'):
                        yeni_lines.pop()
                    print(f"Orphan blok silindi: {i+1}-{j+1}: {line[:60]}")
                    silinen += 1
                    i = j + 1
                    break
            else:
                yeni_lines.append(line)
                i += 1
        else:
            yeni_lines.append(line)
            i += 1

    new_content = '\n'.join(yeni_lines)
    with open(SRC, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"\nToplam silinen orphan blok: {silinen}")
    print(f"Yeni satir sayisi: {len(new_content.splitlines())}")


if __name__ == "__main__":
    main()
