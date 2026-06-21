# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f'Total lines: {len(lines)}')

# Find all lines with suspicious characters
for i, line in enumerate(lines):
    # Check for:
    # 1. '?' in string literals (should be Turkish chars)
    # 2. 'ı' outside of Turkish words (often a mistake)
    # 3. Multiple consecutive '?'
    # 4. Lines with 'isSet ı' (should be 'isSet ?')
    stripped = line.strip()
    if stripped:
        # Check if line has ? in string context
        if "'?" in line or '".?' in line:
            print(f'L{i+1}: {line.rstrip()[:100]}')
        if 'isSet ı ' in line:
            print(f'L{i+1} (isSet ı): {line.rstrip()[:100]}')
        if 'isSet ?' not in line and 'isSet ?' in line.replace('ı', '?'):
            print(f'L{i+1} (isSet wrong): {line.rstrip()[:100]}')