# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f'Lines: {len(lines)}')

# Check L1555 and L1695
for lineno in [1554, 1694]:
    line = lines[lineno]
    print(f'L{lineno+1}: {repr(line[:100])}')

# Fix L1555 - find the edge function line
for i, line in enumerate(lines):
    if "Anahtarlar" in line or "kaydettikten" in line or "edge function" in line:
        print(f'L{i+1}: {line[:100]}')

# Fix L1695 - hintText
for i, line in enumerate(lines):
    if 'hintText' in line and "'?" in line:
        print(f'L{i+1} hint: {repr(line[:100])}')
    if 'h' in line and '?' in line and i > 1690 and i < 1700:
        print(f'L{i+1}: {repr(line[:100])}')

# Apply remaining fixes
# L1555: "Anahtarlar? kaydettikten sonra edge function'? deploy edin:"
for i, line in enumerate(lines):
    if "kaydettikten sonra edge function" in line:
        # Fix: remove the ? before kaydettikten and the '? after function
        new_line = line.replace("? kaydettikten", " kaydettikten")
        new_line = new_line.replace("function'?", "function'")
        if new_line != line:
            lines[i] = new_line
            print(f'Fixed L{i+1}: {line[:60]}')

# L1695: hintText
for i, line in enumerate(lines):
    if i == 1694:  # 0-indexed
        # The hint should be asterisks or dots
        new_line = line.replace("'????????????'", "'••••••••••••'")
        if new_line != line:
            lines[i] = new_line
            print(f'Fixed L{i+1} hintText')

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('Written')