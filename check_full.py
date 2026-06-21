# -*- coding: utf-8 -*-
path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f'Total: {len(lines)} lines')
# Track open brackets/lists/parens
open_list = 0  # [
open_paren = 0  # (
prev_indent = 0
stack = []  # (type, indent)

for i, line in enumerate(lines):
    stripped = line.rstrip('\n\r')
    if not stripped:
        continue
    leading = len(line) - len(line.lstrip())
    # Skip all-whitespace or comment lines
    if stripped.startswith('//') or stripped.startswith('/*') or stripped.startswith('*'):
        continue
    # Check for list close
    if stripped.startswith('],') or stripped.startswith(']'):
        if stack and stack[-1][0] == 'list' and stack[-1][1] < leading:
            # Closed a list
            stack.pop()
    # Check for paren close
    if stripped.startswith('),') or stripped.startswith(');') or stripped == '),' or stripped == ');':
        pass
    # Check for interesting lines
    if i >= 990 and i <= 1025:
        print(f'L{i+1}({leading:3d}): {stripped[:80]}')