# -*- coding: utf-8 -*-
path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')

# Track bracket depth from L947 to L1018
# We'll count [ and ] per line
depth = 0
open_items = []  # stack of (type, indent, line)

for i in range(946, 1020):
    if i >= len(lines):
        break
    line = lines[i]
    stripped = line.strip()
    leading = len(line) - len(line.lstrip())
    
    # Count opening/closing
    opens = stripped.count(b'[') + stripped.count(b'(') + stripped.count(b'{')
    closes = stripped.count(b']') + stripped.count(b')') + stripped.count(b'}')
    
    # Also check for list/paren open patterns
    if b'children: [' in stripped or b'items: [' in stripped or b'list: [' in stripped:
        opens += 1
    if stripped.startswith(b'])'):
        closes += 1
    if stripped.startswith(b')') or stripped.startswith(b']'):
        # Check if it's closing
        if stripped in [b']', b')', b'}']:
            closes += 1
        elif b']);' in stripped or b']);' in stripped:
            closes += 1
            opens += 1
    
    for _ in range(opens):
        depth += 1
    for _ in range(closes):
        depth -= 1
    
    if opens > 0 or closes > 0:
        print(f'L{i+1}({leading:3d}): depth={depth:+d} opens={opens} closes={closes} | {stripped[:60]}')