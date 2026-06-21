# -*- coding: utf-8 -*-
path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')
print(f'Total lines: {len(lines)}')

# Show lines 1010-1025
for i in range(1009, 1025):
    if i < len(lines):
        line = lines[i]
        stripped = line.strip()
        leading = len(line) - len(line.lstrip())
        print(f'L{i+1}({leading:3d}): {repr(line[:80])}')