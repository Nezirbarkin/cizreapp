# -*- coding: utf-8 -*-
path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()
print(f'Total: {len(lines)} lines')
# Check indentation 1015-1025
for i in range(1014, 1025):
    line = lines[i]
    stripped = line.rstrip('\n\r')
    leading = len(line) - len(line.lstrip())
    print(f'L{i+1}({leading:3d}): {stripped[:80]}')