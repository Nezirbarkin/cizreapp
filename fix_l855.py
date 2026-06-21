# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')

# L855 is index 854
line = lines[854]
print(f'L855 length: {len(line)}')

# Find the pattern: ...''). -> should be ...');').
# The wrong ending: ...''.)) -> correct: ...');).
wrong_end = b" OpenAI).''))"
correct_end = b" OpenAI.');"

if wrong_end in line:
    new_line = line.replace(wrong_end, correct_end, 1)
    lines[854] = new_line
    print(f'Fixed L855 ending')
    print(f'  Before: {line[-20:]}')
    print(f'  After: {new_line[-20:]}')
else:
    print(f'Pattern not found')
    # Try to find what we have
    # Find the last bytes
    print(f'Last 30 bytes: {line[-30:].hex()}')
    print(f'Last 30 text: {line[-30:]}')

result = b'\r\n'.join(lines)
with open(path, 'wb') as f:
    f.write(result)
print(f'Written {len(result)} bytes')