# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')
print(f'Lines: {len(lines)}')

# Fix 1: L1016 (index 1015): "      ]," -> "      ),"
# Fix 2: L1018 (index 1017): "    );" -> "      );"
# Fix 3: L2238 (index 2237): providers[0]['id'], -> providers[0]['id'] as String,

changes = 0

# Fix 1: L1016
if len(lines) > 1015:
    if lines[1015] == b'      ],':
        lines[1015] = b'      ),'
        changes += 1
        print('Fixed L1016: ], -> ),')
    else:
        print(f'L1016 expected "      ],", got: {lines[1015]}')

# Fix 2: L1018
if len(lines) > 1017:
    if lines[1017] == b'    );':
        lines[1017] = b'      );'
        changes += 1
        print('Fixed L1018:     ); ->       );')
    else:
        print(f'L1018 expected "    );", got: {lines[1017]}')

# Fix 3: L2238
if len(lines) > 2237:
    line = lines[2237]
    if b"providers[0]['id']," in line:
        new_line = line.replace(b"providers[0]['id'],", b"providers[0]['id'] as String,")
        lines[2237] = new_line
        changes += 1
        print('Fixed L2238: providers[0][id] -> providers[0][id] as String')
    else:
        print(f'L2238 pattern not found: {line[:60]}')

result = b'\r\n'.join(lines)
with open(path, 'wb') as f:
    f.write(result)
print(f'Done: {len(result)} bytes, {changes} changes')