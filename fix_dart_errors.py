# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f'Lines: {len(lines)}')

# All the fixes needed (1-indexed line numbers -> 0-indexed)
fixes = {
    # Line 233: Şablon eklendi
    232: ("'?ablon eklendi'", "'Şablon eklendi'"),
    # Line 257: İptal
    256: ("'?ptal'", "'İptal'"),
    # Line 283: Şablon silindi
    282: ("'?ablon silindi'", "'Şablon silindi'"),
    # Lines 351, 355, 381: debugPrint messages with emoji
    350: ("'? _loadSettings ba?l?yor...'", "'📱 _loadSettings başlıyor...'"),
    354: ("'? _loadSettings ba?ar?l?:'", "'📱 _loadSettings başarılı:'"),
    380: ("'? _loadSettings HATASI:", "'📱 _loadSettings HATASI:"),
    # Line 579: İptal
    578: ("'?ptal'", "'İptal'"),
    # Line 673: İstatistikler
    672: ("'?statistikler'", "'İstatistikler'"),
    # Line 1555: Anahtarları
    1554: ("'? kaydettikten sonra edge function'?", "' kaydettikten sonra edge function'?"),
    # Line 1693: isSet ? (ternary operator - the ı is wrong)
    1692: ("isSet ı 'Yeni anahtar (deıiıtirmek iüin girin)'", "isSet ? 'Yeni anahtar (değiştirmek için girin)'"),
    # Line 1693: API anahtarını yapııtırın
    1692: ("'API anahtarını yapııtı", "'API anahtarını yapıştır"),
    # Line 1695: hintText with placeholder
    1694: ("'? ? ? ? ? ? ? ? ? ? ? ?'", "'• • • • • • • • • • • •'"),
    # Line 1841: İstek
    1840: ("'?stek'", "'İstek'"),
    # Lines 2781, 2951: İptal
    2780: ("'?ptal'", "'İptal'"),
    2950: ("'?ptal'", "'İptal'"),
}

# Apply fixes
changes = 0
for lineno, (wrong, correct) in fixes.items():
    if lineno < len(lines):
        if wrong in lines[lineno]:
            lines[lineno] = lines[lineno].replace(wrong, correct, 1)
            changes += 1
            print(f'Fixed L{lineno+1}: {wrong[:40]}')
        else:
            print(f'NOT FOUND L{lineno+1}: {wrong[:40]}')

print(f'Total changes: {changes}')

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)

print(f'Written {len(lines)} lines')

# Verify
with open(path, 'r', encoding='utf-8') as f:
    verify = f.readlines()

for lineno in [232, 256, 282, 350, 354, 380, 578, 672, 1692, 1694, 1840, 2780, 2950]:
    line = verify[lineno]
    if '?' in line and '?' not in line[:5]:  # suspicious ?
        print(f'L{lineno+1} still has ?: {line[:80]}')