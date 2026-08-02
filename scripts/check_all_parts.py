#!/usr/bin/env python3
"""Tum part dosyalarini tek tek analiz et, gercek error'lari bul."""

import os
import subprocess

PARTS_DIR = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_parts"
PROJECT = r"C:\Users\lenovo\cizreapp"

os.chdir(PROJECT)
for fn in sorted(os.listdir(PARTS_DIR)):
    if not fn.endswith('.dart'):
        continue
    fpath = os.path.join(PARTS_DIR, fn)
    rel_path = os.path.relpath(fpath, PROJECT)
    print(f"=== {fn} ===")
    r = subprocess.run(
        ['C:\\Users\\lenovo\\cizreapp\\.flutter\\bin\\flutter.bat', 'analyze', rel_path] if os.path.exists('C:\\Users\\lenovo\\cizreapp\\.flutter\\bin\\flutter.bat') else ['flutter', 'analyze', rel_path],
        capture_output=True, text=True, timeout=180, shell=True
    )
    out = (r.stdout + r.stderr).strip()
    # Sadece error satirlarini goster
    error_lines = [l for l in out.splitlines() if 'error -' in l]
    if error_lines:
        print(f"  {len(error_lines)} ERROR:")
        for l in error_lines[:5]:
            print(f"    {l[:150]}")
    else:
        info_count = sum(1 for l in out.splitlines() if 'info -' in l or 'warning -' in l)
        print(f"  OK (info/warning: {info_count})")
