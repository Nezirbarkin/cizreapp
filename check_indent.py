# -*- coding: utf-8 -*-
path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Print lines 710-870 with indentation (leading spaces)
for i in range(709, 870):
    line = lines[i]
    stripped = line.rstrip('\n\r')
    leading = len(line) - len(line.lstrip())
    print(f'L{i+1}({leading:3d}): {stripped[:80]}')