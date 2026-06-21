# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f'Total lines: {len(lines)}')

# Fix L1016: remove the extra "      ],"
# Fix L1018: change indent from 4 to 6: "    );" -> "      ),"

changes = 0
for i, line in enumerate(lines):
    stripped = line.rstrip('\n\r')
    leading_spaces = len(line) - len(line.lstrip())
    
    # Fix L1016 (0-indexed: 1015): "      ]," -> remove this line
    if i == 1015 and stripped == '],':
        print(f'L{1016}: Removing extra ],')
        lines[i] = ''
        changes += 1
    
    # Fix L1018 (0-indexed: 1017): "    );" -> "      );"
    if i == 1017 and stripped == ');':
        if leading_spaces == 4:
            print(f'L{1018}: Fixing indent 4 -> 6')
            lines[i] = '      );\n'
            changes += 1
    
    # Also fix L1004 and L1006: remove extra leading spaces
    # "              ? ..." -> "          ? ..."
    if i == 1003 and stripped.startswith('? '):
        print(f'L{1004}: Fixing ternary indent')
        lines[i] = '          ? ' + stripped.lstrip()[2:] + '\n'
        changes += 1
    if i == 1005 and stripped.startswith(': '):
        print(f'L{1006}: Fixing ternary indent')
        lines[i] = '          : ' + stripped.lstrip()[2:] + '\n'
        changes += 1

print(f'Changes: {changes}')

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('Written')