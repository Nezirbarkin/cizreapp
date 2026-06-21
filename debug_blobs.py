# -*- coding: utf-8 -*-
import subprocess, sys
sys.stdout.reconfigure(encoding='utf-8')

result = subprocess.run(['git', 'fsck', '--lost-found'], capture_output=True, text=True, cwd=r'c:\Users\lenovo\cizreapp')
print('fsck done')
blobs = [l.split()[2] for l in result.stdout.split('\n') if 'dangling blob' in l]
print(f'{len(blobs)} blobs found')

found_count = 0
for sha in blobs:
    r = subprocess.run(['git', 'cat-file', '-p', sha], capture_output=True, cwd=r'c:\Users\lenovo\cizreapp')
    if r.returncode == 0:
        c = r.stdout
        if b'AIManagementContent' in c or b'pollinationsKey' in c:
            print(f'MATCH: {sha} ({len(c)} bytes)')
            print(c[:300])
            print('---')
            found_count += 1

print(f'Done: {found_count} matches')