#!/usr/bin/env python3
"""Ana dosyada kalan metot tanimlarini listele."""

import re

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"

with open(SRC, 'r', encoding='utf-8') as f:
    content = f.read()

# Class icindeki metot tanimlarini bul
# Ornek: "  Widget _buildDrawer(...) {"
# Veya: "  Future<void> _loadRealData() async {"
pattern = re.compile(
    r'^  ((?:static\s+)?(?:Widget|Future<[^>]*>|void|bool|int|double|String|List<[^>]*>|Map<[^>]*>|[A-Z][a-zA-Z]*))\s+'
    r'(_[a-zA-Z_][a-zA-Z0-9_]*)\s*\(',
    re.MULTILINE
)

methods = []
for m in pattern.finditer(content):
    line_no = content[:m.start()].count('\n') + 1
    methods.append((line_no, m.group(1), m.group(2)))

print(f"Ana dosyada {len(methods)} metot tanimi kaldi:")
for line, ret, name in methods:
    print(f"  satir {line}: {ret} {name}")
