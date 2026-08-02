#!/usr/bin/env python3
"""Ana dosyadan 14 metodu (gövdeleriyle) part dosyalina tasi, sonra sadece state+build kalsin."""

import os
import re

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"
PARTS_DIR = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_parts"
MISC_PART = os.path.join(PARTS_DIR, "_part_misc_remaining.dart")

# Ana dosyada kalan 14 metot
REMAINING = [
    ("void", "_setupRealtimeSubscription"),
    ("Future<void>", "_loadRealData"),
    ("Widget", "_buildBody"),
    ("Color", "_getReportStatusColor"),
    ("IconData", "_getReportStatusIcon"),
    ("Color", "_getCategoryColor"),
    ("Color", "_parseColor"),
    ("Color", "_getOrderStatusColor"),
    ("Widget", "_buildComingSoon"),
    ("Widget", "_buildInfoRow"),
    ("Color", "_getNotificationStatusColor"),
    ("Color", "_getSupportTicketStatusColor"),
    ("Color", "_getPaymentStatusColor"),
    ("IconData", "_getPaymentIcon"),
]


def find_method_block(content, ret_type, name):
    """Bir metodun baslangicindan (signature) bitisine (kapanis brace) kadar olan araligi bul."""
    # Pattern: return_type method_name(
    pattern = re.compile(
        r'^  (' + re.escape(ret_type) + r')\s+(' + re.escape(name) + r')\s*\(',
        re.MULTILINE
    )
    m = pattern.search(content)
    if not m:
        return None, None
    start = m.start()
    # Brace matching
    paren_depth = 0
    i = start
    found_open = -1
    while i < len(content):
        ch = content[i]
        if ch == '(':
            paren_depth += 1
        elif ch == ')':
            paren_depth -= 1
        if paren_depth == 0 and ch == '{':
            found_open = i
            break
        i += 1
    if found_open < 0:
        return None, None
    brace_depth = 1
    j = found_open + 1
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
                return start, end
        j += 1
    return None, None


def main():
    with open(SRC, 'r', encoding='utf-8') as f:
        content = f.read()

    # Her metodu bul ve govdesini cikar
    extracted = []
    for ret, name in REMAINING:
        start, end = find_method_block(content, ret, name)
        if start is None:
            print(f"BULUNAMADI: {ret} {name}")
            continue
        block = content[start:end]
        extracted.append((name, block))
        # Metodu icerikten cikar
        content = content[:start] + content[end:]

    # _buildBody build tarafindan cagrildigi icin sadece onu ana dosyada tutalim
    # (yoksa build() calismaz)
    # Aslinda hayir - hepsini part dosyasina tasiyalim, build da orada olabilir
    # Cunku build() _buildBody'i cagirir, bu OKEY (part of ayni kutuphane)

    # Yeni part dosyasi olustur
    os.makedirs(PARTS_DIR, exist_ok=True)
    with open(MISC_PART, 'w', encoding='utf-8') as f:
        f.write("part of 'admin_dashboard_screen.dart';\n\n")
        for name, block in extracted:
            # block zaten satir basi 2 boslukla basliyor
            f.write(f"  // --- {name} ---\n")
            # block'un sonundaki newline'i koruyarak yaz
            f.write(block)
            if not block.endswith('\n'):
                f.write('\n')
            f.write('\n')
    print(f"Part dosyasi olusturuldu: {MISC_PART} ({len(extracted)} metot)")

    # Ana dosyaya part direktifi ekle (eger yoksa)
    if "_part_misc_remaining.dart" not in content:
        # part direktiflerinin oldugu yere ekle
        m = re.search(r"(part '[^']+';\n)(?!.*part ')", content, re.DOTALL)
        if m:
            content = content[:m.end()] + "part 'admin_dashboard_parts/_part_misc_remaining.dart';\n" + content[m.end():]

    # Birden fazla bos satiri teke indir
    content = re.sub(r'\n{3,}', '\n\n', content)

    with open(SRC, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"Ana dosya guncellendi: {len(content.splitlines())} satir")


if __name__ == "__main__":
    main()
