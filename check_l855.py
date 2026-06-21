# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')

# Find L855 (index 854)
if 854 < len(lines):
    line = lines[854]
    print(f'L855 length: {len(line)}')
    print(f'L855 hex: {line.hex()}')
    
    # Find the position of every ' in the line
    for i, byte in enumerate(line):
        if byte == 0x27:  # ASCII apostrophe
            print(f'  Apostrophe at byte {i}: context = {line[max(0,i-5):i+5]}')
    
    # Check if line ends properly
    print(f'Last 10 bytes: {line[-10:].hex()}')
    print(f'Last 10 as text: {line[-10:].decode("utf-8", errors="replace")}')