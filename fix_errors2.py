# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f'Lines: {len(lines)}')

# Fix 1: True/False -> true/false in Dart
for i, line in enumerate(lines):
    if ': True' in line or ': True,' in line or ', True' in line:
        new_line = line.replace(': True', ': true').replace(', True', ', true')
        lines[i] = new_line
        print(f'L{i+1}: True -> true')
    if ': False' in line or ': False,' in line or ', False' in line:
        new_line = line.replace(': False', ': false').replace(', False', ', false')
        lines[i] = new_line
        print(f'L{i+1}: False -> false')

# Fix 2: L855 (index 854) - Text missing closing ')'
# Current: "Akıllı routing... ),"
# The Text is: Text('...', style: ...)
# Missing: Text('...' ), -> Text('...', style: ...),)  
# Actually the style already closes. We need to add closing ) for Text after style's )
# Let's check L857-860
for i in range(853, 862):
    print(f'L{i+1}: {repr(lines[i][:80])}')

# Fix 3: L831 - Sğlayıcı -> Sağlayıcı (missing ş)
for i, line in enumerate(lines):
    if "S\u011flay" in line:
        new_line = line.replace("S\u011flay", "Sa\u011flay")
        lines[i] = new_line
        print(f'L{i+1}: Sğlay -> Sağlay')

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('Written')