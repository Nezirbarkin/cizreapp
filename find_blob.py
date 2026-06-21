# -*- coding: utf-8 -*-
import subprocess

blobs = [
    '06c01f80c7dbab3952577450e2d8c7ad3ef2e42a',
    '3c20724067222fdb44c5f55761a4347e02c1f14f',
    '3fc17150adf6bb4d2a2a872845d0dcf487875f35',
    '9541a6ba1ff31b4c8f3fc200ab221d6518c79056',
    'a3c1ea1620c2677a07fc9e253054a7657c6750e5',
    'c1412017124575ac19d8dcf54ee744d4b2d8b3cf',
    '2222681466dcca92028ab7578af64d2d5b65f9cb',
    '5d821114ea8c3e6ca61ad244371a929eafb55828',
    'acc3e09a62cb9d75865fd09820fe950470e87340',
]

for blob in blobs:
    result = subprocess.run(['git', 'cat-file', '-p', blob], capture_output=True, cwd=r'c:\Users\lenovo\cizreapp')
    if result.returncode == 0:
        content = result.stdout
        if b'AIManagementContent' in content or b'ignore_for_file' in content:
            print(f'FOUND! Blob: {blob}')
            print(f'First 200 bytes: {content[:200]}')
            # Save it
            path = r'lib\features\admin\widgets\ai_management_content.dart'
            with open(path, 'wb') as f:
                f.write(content)
            print(f'Saved to {path}')
            break
        else:
            size = len(content)
            first = content[:100]
            print(f'{blob}: {size} bytes, no AI content')
    else:
        print(f'{blob}: error')