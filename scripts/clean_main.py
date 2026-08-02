#!/usr/bin/env python3
"""Ana dosyadan metotları sil, ama güvenli."""
import re
import json

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"
BOUNDS = r"C:\Users\lenovo\cizreapp\scripts\_method_bounds.json"

# Ana dosyada kalacak metotlar
KEEP = {
    "build", "_setupRealtimeSubscription", "_loadRealData", "_buildBody",
    "_buildComingSoon", "_buildInfoRow",
}


def find_method_bounds(lines, method_name):
    pattern_prefix = method_name + "("
    for i in range(len(lines)):
        line = lines[i]
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if indent != 2:
            continue
        if pattern_prefix not in stripped:
            continue
        idx = stripped.index(pattern_prefix)
        if idx == 0:
            continue
        if stripped[idx-1] != ' ':
            continue
        paren_depth = 0
        sig_end_line = i
        for j in range(i, len(lines)):
            for ch in lines[j]:
                if ch == "(":
                    paren_depth += 1
                elif ch == ")":
                    paren_depth -= 1
            if paren_depth == 0:
                sig_end_line = j
                break
        brace_depth = 0
        started = False
        j = sig_end_line
        while j < len(lines):
            for ch in lines[j]:
                if ch == "{":
                    brace_depth += 1
                    started = True
                elif ch == "}":
                    brace_depth -= 1
            if started and brace_depth == 0:
                return i, j
            j += 1
    return None, None


def main():
    with open(SRC, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    with open(BOUNDS, 'r') as f:
        methods = json.load(f)

    # Tüm metotları bul (KEEP hariç) - ama MEVCUT dosyadan
    to_remove_bounds = []
    for name in methods.keys():
        if name in KEEP:
            continue
        start, end = find_method_bounds(lines, name)
        if start is None:
            print(f"  BULUNAMADI (mevcut dosyada): {name}")
            continue
        to_remove_bounds.append((start, end, name))

    print(f"Silinecek: {len(to_remove_bounds)} metot")

    # Sondan başa doğru sil
    to_remove_bounds.sort(key=lambda x: -x[0])
    new_lines = lines[:]
    for start, end, name in to_remove_bounds:
        if end >= len(new_lines):
            print(f"  ATLANDI (sinir asildi): {name} {start}-{end}")
            continue
        # Önceki boş satırı da sil
        delete_start = start
        if start > 0 and new_lines[start-1].strip() == "":
            delete_start = start - 1
        # Sildikten sonra sonraki boş satır da varsa onu da sil
        delete_end = end
        if end + 1 < len(new_lines) and new_lines[end+1].strip() == "":
            delete_end = end + 1
        del new_lines[delete_start:delete_end+1]

    with open(SRC, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    print(f"Ana dosya: {len(lines)} -> {len(new_lines)} satir")


if __name__ == "__main__":
    main()
