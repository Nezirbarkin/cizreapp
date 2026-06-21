# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')
print(f'Lines: {len(lines)}')

# Fix L1017 (index 1016): "      ];" -> "      ],"
# Fix L1019 (index 1018): "    );" -> "  }"
changes = 0

# Fix L1017
if len(lines) > 1016:
    if lines[1016] == b'      ];':
        lines[1016] = b'      ],'
        changes += 1
        print('Fixed L1017: ]; -> ],')

# Fix L1019
if len(lines) > 1018:
    if lines[1018] == b'    );':
        lines[1018] = b'  }'
        changes += 1
        print('Fixed L1019:     ); ->   }')

result = b'\r\n'.join(lines)
with open(path, 'wb') as f:
    f.write(result)
print(f'Done: {changes} changes')