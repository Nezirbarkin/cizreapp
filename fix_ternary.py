# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')
print(f'Lines: {len(lines)}')

# Find lines with problematic patterns
# Pattern 1: `ı const` at start of ternary branches (U+0131 dotless i = 0xC4 0xB1)
# Pattern 2: `ı 'string'` (dotless i before string in ternary)
# Pattern 3: `ı const` in L2079

dotless_i = b'\xc4\xb1'  # Turkish dotless ı (U+0131)

for i, line in enumerate(lines):
    if dotless_i in line:
        # Try to decode and check
        try:
            t = line.decode('utf-8')
            # Check for ternary operator issues
            if 'const ' in t and line.startswith(dotless_i):
                print(f'L{i+1}: starts with dotless ı: {t[:80]}')
            if 'isSet ' in t and dotless_i.decode('utf-8') in t:
                print(f'L{i+1}: isSet with dotless ı: {t[:80]}')
            if ' ı const' in t:
                print(f'L{i+1}: ı const: {t[:80]}')
        except:
            pass

# Fix: Replace dotless ı with ? at the beginning of ternary branches
# In L2079: "ı const Center" -> "? const Center"
# In L1693: "isSet ı 'Yeni..." -> "isSet ? 'Yeni..."
# In L2467: "ı const Center" -> "? const Center"

fixes_needed = []
for i, line in enumerate(lines):
    try:
        t = line.decode('utf-8')
        # Fix 1: starts with ı followed by space and const
        if t.startswith('\u0131 const') or t.startswith('\u0131  const'):
            # Replace leading dotless ı with ?
            new_t = '? ' + t[2:]  # skip the ı and add ?
            new_line = new_t.encode('utf-8')
            fixes_needed.append((i, t[:60], new_t[:60]))
            lines[i] = new_line
        # Fix 2: "isSet ı '" -> "isSet ? '"
        if 'isSet \u0131' in t:
            new_t = t.replace('isSet \u0131', 'isSet ?', 1)
            new_line = new_t.encode('utf-8')
            fixes_needed.append((i, t[:60], new_t[:60]))
            lines[i] = new_line
    except:
        pass

print(f'\nFixes applied: {len(fixes_needed)}')
for i, old, new in fixes_needed:
    print(f'L{i+1}: {old[:50]} -> {new[:50]}')

result = b'\r\n'.join(lines)
with open(path, 'wb') as f:
    f.write(result)
print(f'Written {len(result)} bytes')