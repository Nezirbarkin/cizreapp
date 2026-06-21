# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')
print(f'Lines: {len(lines)}')

dotless_i = b'\xc4\xb1'

for i, line in enumerate(lines):
    if dotless_i in line:
        try:
            t = line.decode('utf-8')
            # Fix: lines starting with spaces + dotless ı + " const"
            if '\u0131 const' in t:
                # Replace dotless ı with ?
                new_t = t.replace('\u0131 const', '? const', 1)
                lines[i] = new_t.encode('utf-8')
                print(f'Fixed L{i+1}: {t[:60]} -> {new_t[:60]}')
        except:
            pass

result = b'\r\n'.join(lines)
with open(path, 'wb') as f:
    f.write(result)
print(f'Written {len(result)} bytes')