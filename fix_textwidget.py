# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')

# Fix L855 (index 854) - Text missing closing ')'
# Find the line with Akıllı routing text
for i, line in enumerate(lines):
    if b'Ak' in line and b'routing' in line:
        print(f'L{i+1}: {line[:80].hex()}')
        print(f'L{i+1}: {line.decode("utf-8", errors="replace")}')

# Fix: Add ) after the string and fix Turkish chars
# Wrong: 'Akıllı routing: Seüili saılayıcı ünce denenir; baıarısız olursa...',
# Correct: 'Akıllı routing: Seçili sağlayıcı önce denenir; başarısız olursa...'),

# Fix Turkish characters in this line
# Seüili -> Seçili
# saılayıcı -> sağlayıcı
# ünce -> önce
# baıarısız -> başarısız

for i, line in enumerate(lines):
    if b'Ak' in line and b'routing' in line:
        t = line.decode('utf-8', errors='replace')
        # Fix Turkish
        t = t.replace('Seüili', 'Seçili')
        t = t.replace('saılayıcı', 'sağlayıcı')
        t = t.replace('ünce', 'önce')
        t = t.replace('baıarısız', 'başarısız')
        # Add closing ) if missing
        # The line ends with: ...'), or should end with ...'),)
        if not t.rstrip().endswith("'),)"):
            if t.rstrip().endswith("',"):
                # Missing ) at the end of Text widget
                t = t.rstrip()[:-1] + "'),)" + '\n'
            elif t.rstrip().endswith("'),"):
                # Already has proper closing
                pass
        new_line = t.encode('utf-8')
        if new_line != line:
            lines[i] = new_line
            print(f'Fixed L{i+1}')
            print(f'  Before: {line.decode("utf-8", errors="replace")[:60]}')
            print(f'  After: {t[:60]}')

result = b'\r\n'.join(lines)
with open(path, 'wb') as f:
    f.write(result)
print(f'Written {len(result)} bytes')