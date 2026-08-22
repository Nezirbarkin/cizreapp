#!/usr/bin/env python
# -*- coding: utf-8 -*-
import io

PATH = 'supabase/migrations/20260804000002_fill_app_contract_gaps.sql'
data = open(PATH, 'rb').read()
lines = data.split(b'\n')

def is_border(ln_replaced):
    # comment line made only of '=' , box chars, spaces, and replacement chars
    s = ln_replaced.strip()
    if not s.startswith('--'):
        return False
    rest = s[2:].strip()
    if rest == '':
        return False
    for ch in rest:
        if ch in ('═', '�', '=', ' '):
            continue
        return False
    return True

fixed_count = 0
report = []
for i, ln in enumerate(lines):
    try:
        ln.decode('utf-8')
        continue  # already valid
    except UnicodeDecodeError:
        pass
    # This line has invalid bytes.
    replaced = ln.decode('utf-8', 'replace')
    line_no = i + 1
    if is_border(replaced):
        # Replace with a clean ASCII border of '='.
        new_ln = b'-- ' + b'=' * 74
        report.append('LINE %d: border -> ASCII =' % line_no)
        lines[i] = new_ln
        fixed_count += 1
    else:
        # Non-border invalid line: do targeted byte surgery.
        # Strategy: replace any run of bytes that are not valid ASCII-printable
        # or valid UTF-8 with their intended form. We rebuild the line by
        # decoding valid segments and re-encoding them; invalid bytes get
        # mapped to '?' but for known Turkish words we patch afterwards.
        # Simpler: replace the whole invalid byte region between 'saklan' and 'yor'
        if b'saklan' in ln and b'yor' in ln:
            # Find 'saklan' then take bytes until 'yor' that follows.
            idx = ln.index(b'saklan')
            seg_start = idx + len(b'saklan')
            # find next 'yor' after seg_start
            yor_idx = ln.index(b'yor', seg_start)
            bad = ln[seg_start:yor_idx]
            # Replace the invalid middle bytes with correct UTF-8 for 'i' (dotless): U+0131 = C4 B1
            correct = b'\xc4\xb1'
            new_ln = ln[:seg_start] + correct + ln[yor_idx:]
            # verify
            try:
                new_ln.decode('utf-8')
                report.append('LINE %d: turkish word fixed -> %s' % (line_no, new_ln.decode('utf-8')))
                lines[i] = new_ln
                fixed_count += 1
            except UnicodeDecodeError as e:
                report.append('LINE %d: STILL INVALID after fix: %s' % (line_no, e))
        else:
            report.append('LINE %d: unhandled invalid line (manual review): %s' % (line_no, replaced))

out = b'\n'.join(lines)
# Final sanity: ensure whole file is valid UTF-8 now.
try:
    out.decode('utf-8')
    print('OK: entire file is valid UTF-8 after fix.')
except UnicodeDecodeError as e:
    print('WARN: file still has invalid bytes at', e.start, e.reason)

open(PATH, 'wb').write(out)
print('Fixed %d line(s):' % fixed_count)
for r in report:
    print('  -', r)
