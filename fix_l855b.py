# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')
line = lines[854]

# Fix: OpenAI).'')), -> OpenAI.');\n
# 2e = .
# 27 27 29 2c = ''),
# Replace with: 27 3b 29 2c = ';),

wrong = b'OpenAI).' + b'\x27\x27\x29\x2c'
correct = b'OpenAI.' + b'\x27\x3b\x29\x2c'

print(f'Looking for: {wrong.hex()}')
print(f'Line contains: {b"OpenAI)." in line}')

idx = line.rfind(b'OpenAI)')
print(f'OpenAI) at: {idx}')
if idx >= 0:
    snippet = line[idx:idx+20]
    print(f'Snippet: {snippet.hex()} = {snippet}')

# Try the replacement
if wrong in line:
    new_line = line.replace(wrong, correct, 1)
    lines[854] = new_line
    print(f'Fixed!')
    print(f'New ending: {new_line[-30:]}')
    result = b'\r\n'.join(lines)
    with open(path, 'wb') as f:
        f.write(result)
    print(f'Written {len(result)} bytes')
else:
    print('Not found - trying alternative')
    # Try with just the '')), part
    alt_wrong = b'\x27\x27\x29\x2c\x29\x0a'
    alt_correct = b'\x27\x3b\x29\x2c\x0a'
    if alt_wrong in line:
        print(f'Found alt pattern')
        new_line = line.replace(alt_wrong, alt_correct, 1)
        lines[854] = new_line
        result = b'\r\n'.join(lines)
        with open(path, 'wb') as f:
            f.write(result)
        print('Fixed alt')
    else:
        print('Alt pattern not found either')
        print(f'Last 20 hex: {line[-20:].hex()}')