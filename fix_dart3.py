# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Fix all remaining corrupted Turkish strings
# Pattern: 'ı' in wrong places (Turkish dotless ı used instead of 'i' or wrong char)
# Pattern: '?' in string literals where Turkish chars should be

fixes = [
    # L31: API Anahtarlar?
    (30, "Anahtarlar?", "Anahtarları"),
    # L671: API Anahtarlar?
    (670, "Anahtarlar?", "Anahtarları"),
    # L1315: API anahtarlarını aıaııya yapııtırın
    (1314, "aıaııya", "güvenliğe"),
    (1314, "yapııtırın", "yapıştırın"),
    # L1692: deıiıtirmek iüin
    (1691, "deıiıtirmek iüin", "değiştirmek için"),
    # L1315: Anahtarlar ıifreli
    (1314, "Anahtarlar ıifreli", "Anahtarlar şifreli"),
    # L1555: remaining fix
    (1554, "Anahtarlar? kaydettikten", "Anahtarları kaydettikten"),
]

changes = 0
for lineno, wrong, correct in fixes:
    if lineno < len(lines):
        if wrong in lines[lineno]:
            lines[lineno] = lines[lineno].replace(wrong, correct, 1)
            changes += 1
            print(f'Fixed L{lineno+1}: {wrong[:30]} -> {correct[:30]}')
        else:
            print(f'NOT FOUND L{lineno+1}: {repr(wrong[:30])}')

print(f'Changes: {changes}')

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('Written')