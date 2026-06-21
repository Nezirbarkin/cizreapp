# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')
print(f'Lines: {len(lines)}')

# Problem: after FilledButton.icon at L1014 "        )," closes FilledButton.icon
# But there are extra lines after:
# L1016: "      )," - extra
# L1018: "      ];" - extra
# L1019: "  }"   - wrong (should be 4 spaces for ListView closing)

# Also L1017 and L1019 are new errors after our fixes.
# Let's check current state of lines 1012-1025
for i in range(1011, 1025):
    if i < len(lines):
        print(f'L{i+1}: {repr(lines[i][:80])}')