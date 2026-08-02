#!/usr/bin/env python3
"""Her metot adını kullanarak ana dosyada tanımı bul ve sil."""

import os
import re

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"
PARTS_DIR = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_parts"


def find_and_remove_method(content, method_name):
    """Ana dosyada method_name tanımını bul ve sil."""
    pattern = re.compile(
        r'^  (?:static\s+)?(?:Widget|Future<[^>]*>|void|bool|int|double|String|List<[^>]*>|Map<[^>]*>)\s+'
        + re.escape(method_name) + r'\s*\(',
        re.MULTILINE
    )
    m = pattern.search(content)
    if not m:
        return content, False
    start = m.start()
    # Brace matching
    paren_depth = 0
    i = start
    sig_end = -1
    while i < len(content):
        ch = content[i]
        if ch == '(':
            paren_depth += 1
        elif ch == ')':
            paren_depth -= 1
        if paren_depth == 0 and ch == '{':
            sig_end = i
            break
        i += 1
    if sig_end < 0:
        return content, False
    brace_depth = 1
    j = sig_end + 1
    while j < len(content):
        ch = content[j]
        if ch == '{':
            brace_depth += 1
        elif ch == '}':
            brace_depth -= 1
            if brace_depth == 0:
                end = j + 1
                if end < len(content) and content[end] == '\n':
                    end += 1
                # Önceki boş satırı da sil
                while start > 0 and content[start-1] in ' \t':
                    start -= 1
                if start > 0 and content[start-1] == '\n':
                    start -= 1
                return content[:start] + content[end:], True
        j += 1
    return content, False


def main():
    with open(SRC, 'r', encoding='utf-8') as f:
        content = f.read()

    # Part dosyalarından method_name'leri topla
    method_names = set()
    for fn in os.listdir(PARTS_DIR):
        if not fn.endswith('.dart'):
            continue
        fpath = os.path.join(PARTS_DIR, fn)
        with open(fpath, 'r', encoding='utf-8') as f:
            for m in re.finditer(r'// --- (_[a-zA-Z_][a-zA-Z0-9_]*) ---', f.read()):
                method_names.add(m.group(1))

    print(f"Part dosyalarinda {len(method_names)} metot adi bulundu")

    # Her birini ana dosyadan kaldır
    total_removed = 0
    not_found = []
    for name in sorted(method_names):
        content, removed = find_and_remove_method(content, name)
        if removed:
            total_removed += 1
        else:
            not_found.append(name)

    with open(SRC, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"Silinen: {total_removed}")
    print(f"Bulunamayan: {len(not_found)}")
    if not_found:
        print(f"  Ornekler: {not_found[:10]}")
    print(f"Dosya: {len(content.splitlines())} satir")


if __name__ == "__main__":
    main()
