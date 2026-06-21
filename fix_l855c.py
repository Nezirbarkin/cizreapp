# -*- coding: utf-8 -*-
path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

# Fix: ');), -> ');
# 3b = ;  29 = )  2c = ,  29 = )  0a = \n
wrong = b'\x27\x3b\x29\x2c\x29\x0a'
correct = b'\x27\x3b\x29\x2c\x0a'

if wrong in raw:
    raw = raw.replace(wrong, correct)
    with open(path, 'wb') as f:
        f.write(raw)
    print('Fixed: );), -> );')
else:
    print('Not found')
    # Check what we have
    idx = raw.find(b"OpenAI.'")
    if idx >= 0:
        print(f'Context: {raw[idx:idx+20]}')