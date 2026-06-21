# -*- coding: utf-8 -*-
import subprocess, os

# Check current state
path = r'lib\features\admin\widgets\ai_management_content.dart'
print(f'Current file: {os.path.getsize(path)} bytes')

# Get ALL dangling blobs and check for our file
result = subprocess.run(['git', 'fsck', '--lost-found'], capture_output=True, text=True, cwd=r'c:\Users\lenovo\cizreapp')
blobs = []
for line in result.stdout.split('\n'):
    if 'dangling blob' in line:
        parts = line.split()
        if len(parts) >= 3:
            sha = parts[2]
            blobs.append(sha)

print(f'Found {len(blobs)} dangling blobs')

# Search all blobs for our file
for sha in blobs:
    r = subprocess.run(['git', 'cat-file', '-p', sha], capture_output=True, cwd=r'c:\Users\lenovo\cizreapp')
    if r.returncode == 0:
        content = r.stdout
        size = len(content)
        # Our file should be ~60KB with AIManagementContent class
        if b'AIManagementContent' in content and size > 50000:
            print(f'LIKELY MATCH! {sha} ({size} bytes)')
            with open(path, 'wb') as f:
                f.write(content)
            print('SAVED!')
            break
        elif b'AIManagementContent' in content:
            print(f'Small match: {sha} ({size} bytes)')

# Also check git reflog for old file versions
print('\nChecking reflog...')
reflog = subprocess.run(['git', 'reflog', '--all'], capture_output=True, text=True, cwd=r'c:\Users\lenovo\cizreapp')
print(reflog.stdout[:500])