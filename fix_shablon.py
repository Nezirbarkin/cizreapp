# -*- coding: utf-8 -*-
path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    d = f.read()

# Fix ıablon -> Şablon (dotless ı + ablon = ıablon)
# ı = c4 b1, Ş = c5 9e
wrong = b'\xc4\xb1ablon'
correct = b'\xc5\x9eablon'
count = d.count(wrong)
print(f'Found {count} ıablon')
if count > 0:
    d = d.replace(wrong, correct)
    with open(path, 'wb') as f:
        f.write(d)
    print('Fixed')