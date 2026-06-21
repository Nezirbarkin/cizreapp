# -*- coding: utf-8 -*-
import subprocess

candidates = ['f0412e4b9b2196970e83a2883fd70ddb84d5281e',
    '2222681466dcca92028ab7578af64d2d5b65f9cb',
    'acc3e09a62cb9d75865fd09820fe950470e87340',
    '97041f4cc5a968c74ac822d8cbd4fcb00df24d89',
    'eca8ae002b4ac30318f5d29ac87ce5384292923a',
    '2b0f06040730f75fc60893088e2d76761188c9db',
    '785582ecea89ce629a066ff7e84608b5f960a3ea',
    '39f6cdb039ea1e35f75ece70fdac2192a68d6c2d',
    '9237966bd6dd70bfb07495a64d82e052f9cd7d5f',
    '92f91574546674e67143bb9300b87f00a68d2e06',
    'e059b0ce0694574e1cfa9ca0a0e7a2984ba808b4',
    'e4da294eb6ffa9f40ecfd5386e2dcef7f64e4ee3',
    'a3db484aa361e23c7632d2f1ac9881fa05e54489',
    'da1b3c8f4ce373936dbdc0908648dfff0607c45f',
    '27bca1fd010b973b0464b97c86c038af0d128589']

path = r'lib\features\admin\widgets\ai_management_content.dart'
found = False

for sha in candidates:
    r = subprocess.run(['git', 'cat-file', '-p', sha], capture_output=True, cwd=r'c:\Users\lenovo\cizreapp')
    if r.returncode == 0:
        content = r.stdout
        if b'AIManagementContent' in content and b'_buildProviderDropdown' in content:
            print(f'FOUND MATCH! {sha} ({len(content)} bytes)')
            print(f'First 100: {content[:100]}')
            with open(path, 'wb') as f:
                f.write(content)
            print(f'SAVED to {path}')
            found = True
            break
        elif b'AIManagementContent' in content:
            print(f'Partial match: {sha} ({len(content)} bytes)')

if not found:
    print('No match found in large blobs')
    # Try ALL blobs
    result = subprocess.run(['git', 'fsck', '--lost-found'], capture_output=True, text=True, cwd=r'c:\Users\lenovo\cizreapp')
    all_blobs = [l.split()[2] for l in result.stdout.split('\n') if 'dangling blob' in l]
    print(f'Trying all {len(all_blobs)} blobs...')
    for sha in all_blobs:
        r = subprocess.run(['git', 'cat-file', '-p', sha], capture_output=True, cwd=r'c:\Users\lenovo\cizreapp')
        if r.returncode == 0 and b'AIManagementContent' in r.stdout:
            print(f'Match: {sha} ({len(r.stdout)} bytes)')