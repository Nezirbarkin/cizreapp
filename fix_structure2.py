# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'lib\features\admin\widgets\ai_management_content.dart'
with open(path, 'rb') as f:
    raw = f.read()

lines = raw.split(b'\r\n')
print(f'Lines: {len(lines)}')

# Fix: Remove the extra "      )," (L1016, index 1015)
# and keep "      );" (L1018, index 1017) as the closing of FilledButton.icon

# Strategy: replace the sequence from L1014-L1018 with correct version
# Current L1012: "          ),"  (closes styleFrom)
# Current L1014: "        ),"    (closes FilledButton.icon - EXTRA)
# Current L1016: "      ),"     (closes ??? - EXTRA)
# Current L1018: "      );"    (keeps as final closing)
# 
# CORRECT: L1012: "          ),"  (closes styleFrom)
#          L1014: REMOVE (extra)
#          L1016: REMOVE (extra) 
#          L1018: "      );"    (keeps as final closing)

# Replace lines 1014-1017 (0-indexed: 1013-1016) with a single empty line
# Actually let's replace L1014 (index 1013) and L1016 (index 1015) with empty lines
# and shift L1018 up

# Better approach: just replace the content from L1014-L1017 with proper structure
# Current:
# L1014 (8sp): "        ),"
# L1015: empty
# L1016 (6sp): "      ),"
# L1017: empty
# L1018 (6sp): "      );"
# 
# Should be:
# L1014 (8sp): "        ),"   <- same (closes styleFrom)
# L1015: empty
# L1016: REMOVE this line entirely
# L1017: empty  
# L1018: REMOVE "      );" and replace with content of what follows

# Actually: L1018 "      );" IS the correct closing for FilledButton.icon.
# The problem is L1016 "      )," which is EXTRA.
# And the depth says after L1018, we're at -1, meaning the ListView children
# should be closed by a "], " at the ListView level.
# 
# But wait - L1014's ")," closes what? 
# Let me trace again:
# L998: FilledButton.icon(  -> depth +1 (parens)
# L1002-1003: ternary expression, already counted
# L1006: style: FilledButton.styleFrom(  -> depth +1 (parens)
# L1012: "),"  -> depth -1 (closes styleFrom) 
# L1014: "),"  -> ??? what does this close?
# 
# Looking at indentation: FilledButton.icon has 8 spaces.
# L1014 "        )," has 8 spaces - same level as icon:
#   icon: _isSaving
#       ? ...
#       : ...,
#   label: ...,
#   style: FilledButton.styleFrom(
#       ...
#   ),        <- L1012, closes styleFrom
# ),          <- L1014, closes FilledButton.icon
# 
# So L1014 ")," IS the correct closing of FilledButton.icon!
# And L1016 "      )," and L1018 "      );" are EXTRA.
# 
# After removing L1014, L1018 becomes L1016, and we need "      );" at the right indent.

# FIX: Remove lines 1016 and 1018 (0-indexed: 1015 and 1017)
# and keep the structure correct

# Let me just remove L1016 and L1018 and replace them with proper closing
# New L1016 should be "      );" (6 spaces for closing ListView children + ListView parens)
# But that doesn't work because L1014 "        )," is ALREADY closing FilledButton.icon.

# I think the real issue: L1016 "      )," is trying to close something at 6-space level.
# L1018 "      );" is also at 6-space level.
# But after L1014's ")", the depth should be 1 (ListView children).
# Then L1016 ")" would close that, leaving depth 0.
# Then L1018 ")" would close the ListView parens, leaving depth -1 (bad).
# 
# So: REMOVE L1016 and L1018. Keep L1014 "        )," as the FilledButton.icon closing.
# And after L1014, we need "      ],  " (to close children list) and "    );" (to close ListView)

# Fix: Replace L1016 + L1018 with "      ],  " + "    );  "

new_lines = []
for i, line in enumerate(lines):
    if i == 1015:  # L1016 (index 1015)
        # Skip this line (extra "      ),")
        print(f'Removing L1016: {repr(lines[i])}')
        continue
    if i == 1017:  # L1018 (index 1017)
        # Replace with proper closing for ListView
        # "      );" -> becomes "      ],  " + "    );  " but that's two lines
        # Simpler: just change "      );" to "      ],"
        new_lines.append(b'      ],')  # close children list
        print(f'Replacing L1018 with "], " and "); "')
        continue
    new_lines.append(line)

result = b'\r\n'.join(new_lines)
with open(path, 'wb') as f:
    f.write(result)
print(f'Written {len(result)} bytes, {len(new_lines)} lines')