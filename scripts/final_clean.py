#!/usr/bin/env python3
"""
Her part dosyasındaki metot gövdesini ana dosyada ara, bul ve sil.
"""

import os
import re

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"
PARTS_DIR = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_parts"


def find_and_remove(content, signature):
    """Ana dosyada signature içeren satırdan başlayan bloğu bul ve sil."""
    lines = content.split('\n')
    # signature'ı içeren satırı bul
    start = None
    for i, line in enumerate(lines):
        if signature in line and line.startswith('  ') and not line.startswith('   '):
            # Metot tanımı olmalı
            stripped = line.lstrip()
            if re.match(r'(?:static\s+)?(?:Widget|Future<[^>]*>|void|bool|int|double|String|List<[^>]*>|Map<[^>]*>)\s+', stripped):
                # Parantezleri say, gövde başlangıcını bul
                start = i
                paren_depth = 0
                in_sig = False
                for j in range(i, len(lines)):
                    for ch in lines[j]:
                        if ch == '(':
                            paren_depth += 1
                        elif ch == ')':
                            paren_depth -= 1
                        if paren_depth == 0 and ch == '{':
                            in_sig = True
                            brace_depth = 1
                            for k in range(j+1, len(lines)):
                                brace_depth += lines[k].count('{') - lines[k].count('}')
                                if brace_depth == 0:
                                    # k+1 boş satır dahil
                                    end = k + 1
                                    if end < len(lines) and lines[end].strip() == "":
                                        end += 1
                                    # Sil
                                    del lines[start:end]
                                    return '\n'.join(lines), True
                            return content, False
                return content, False
    return content, False


def main():
    with open(SRC, 'r', encoding='utf-8') as f:
        content = f.read()

    # Tüm part dosyalarını oku ve her metot için imza ara
    total_removed = 0
    for fn in os.listdir(PARTS_DIR):
        if not fn.endswith('.dart'):
            continue
        fpath = os.path.join(PARTS_DIR, fn)
        with open(fpath, 'r', encoding='utf-8') as f:
            part_content = f.read()

        # Metot imzalarını bul: "  Widget _methodName(" veya "  Future<...> _methodName(" vs.
        for m in re.finditer(r'^// --- (_[a-zA-Z_][a-zA-Z0-9_]*) ---\n((?:  .*\n)*)', part_content, re.MULTILINE):
            method_name = m.group(1)
            method_body = m.group(2)
            # İlk satır imza
            first_line = method_body.split('\n')[0]
            # Ana dosyada ara
            new_content, removed = find_and_remove(content, first_line.lstrip())
            if removed:
                content = new_content
                total_removed += 1
            else:
                # İmzayı farklı formatta ara
                stripped = first_line.strip()
                # "Widget _methodName(...) {" veya "Widget _methodName(...) async {"
                m2 = re.match(r'(?:Widget|Future<[^>]*>|void|bool|int|double|String|List<[^>]*>|Map<[^>]*>)\s+(_[a-zA-Z_][a-zA-Z0-9_]*)\s*\(', stripped)
                if m2:
                    method_name_actual = m2.group(1)
                    # Ana dosyada method_name_actual içeren tanımı ara
                    new_content, removed = find_and_remove(content, method_name_actual)
                    if removed:
                        content = new_content
                        total_removed += 1
                    else:
                        print(f"  BULUNAMADI: {method_name}")

    with open(SRC, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"Toplam: {total_removed} metot silindi")
    print(f"Dosya: {len(content.splitlines())} satir")


if __name__ == "__main__":
    main()
