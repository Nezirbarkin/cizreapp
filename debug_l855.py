# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')

# Print lines 853-862 with their byte content
for i in range(853, 863):
    line = lines[i]
    print(f'L{i+1} (len={len(line)}): {line}')

# Specifically check L855
print()
print('L855 specific:')
line = lines[854]
print(f'  Bytes: {line}')
print(f'  Hex: {line.hex()}')
print(f'  Text: {line.decode("utf-8", errors="replace")}')