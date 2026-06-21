# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')
print(f'Total: {len(lines)} lines')

# Find the "    );" lines
for i, line in enumerate(lines):
    stripped = line.strip()
    if stripped == b');':
        leading = len(line) - len(line.lstrip())
        print(f'L{i+1} ("    );"): {leading} spaces, content={line}')

# Also find "      ]," lines
for i, line in enumerate(lines):
    if b']' in line and b',' in line:
        leading = len(line) - len(line.lstrip())
        if leading < 20:
            print(f'L{i+1} (]`,): {leading} spaces, content={line}')