# -*- coding: utf-8 -*-
import subprocess, os

path = r'lib\features\admin\widgets\ai_management_content.dart'
print(f'Current file size: {os.path.getsize(path)} bytes')

# Search all git objects for files with our content
# We need blobs that are ~63KB and contain our key content

# Get all blobs from git ls-tree -r HEAD
result = subprocess.run(['git', 'ls-tree', '-r', '--blob', 'HEAD'], capture_output=True, text=True, cwd=r'c:\Users\lenovo\cizreapp')
blobs = []
for line in result.stdout.split('\n'):
    parts = line.split()
    if len(parts) >= 2:
        size = int(parts[2])
        sha = parts[3]
        blobs.append((sha, size))

print(f'Found {len(blobs)} blobs in HEAD')

# Also check git reflog for the file
reflog = subprocess.run(['git', 'reflog', '--all'], capture_output=True, text=True, cwd=r'c:\Users\lenovo\cizreapp')
print(f'Reflog: {reflog.stdout[:200]}')

# Check if there's a backup in .git/refs/heads or similar
# Also check for .git/ORIG_HEAD or .git/FETCH_HEAD
for ref in ['ORIG_HEAD', 'HEAD', 'FETCH_HEAD']:
    try:
        with open(rf'c:\Users\lenovo\cizreapp\.git\{ref}', 'rb') as f:
            content = f.read()
            print(f'{ref}: {len(content)} bytes')
    except:
        pass

# Check git stash
stash = subprocess.run(['git', 'stash', 'list'], capture_output=True, text=True, cwd=r'c:\Users\lenovo\cizreapp')
print(f'Stash list: {stash.stdout[:200]}')