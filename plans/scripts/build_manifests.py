import os, re, sys
from datetime import datetime

sys.stdout.reconfigure(encoding='utf-8')
base = r"C:\Users\lenovo\cizreapp\supabase"
mig_dir = os.path.join(base, "migrations")
arc_dir = os.path.join(base, "archive")

# === ARCHIVE INVENTORY ===
arc = ["# Arsiv Envanteri", "", f"**Tarih:** {datetime.now().strftime('%Y-%m-%d')}  ", 
       "**Amac:** Production'a uygulanmis ama artik referans olarak duran, veya uygulanmamis/uygulanamaz dosyalar.",
       "**Uyari:** Bu dosyalar **hicbir kosulda** yeniden calistirilmamali. Sadece referans icindir.", "", "---", ""]

for root, dirs, files in os.walk(arc_dir):
    rel = os.path.relpath(root, base)
    if not files: continue
    arc.append(f"## `{rel}`")
    arc.append(f"**{len(files)} dosya**")
    arc.append("")
    for f in sorted(files):
        if not f.endswith('.sql'): continue
        full = os.path.join(root, f)
        size = os.path.getsize(full)
        reason = "Tarih formatina uygun degil / tek seferlik fix"
        if 'DEBUG' in f.upper() or 'debug_' in f or 'check_' in f.lower() or 'query' in f.lower():
            reason = "Debug/analiz sorgusu - production'a deploy edilmemis yardim dosyasi"
        elif f.lower().startswith('fix_'):
            reason = "Eski fix, yeni migration'larla supersede edilmis"
        elif 'api_key' in f.lower() or 'gemini' in f.lower() or 'groq' in f.lower() or 'insert_ai_settings' in f.lower():
            reason = "API KEY/secret iceriyor - guvenlik nedeniyle arsivde"
        elif f.upper() in ('FINAL_COMMISSION_FIX.sql', 'COMMISSION_SYSTEM_COMPLETE_FIX.sql'):
            reason = "Commission sistemi eski fix varyanti"
        elif 'product_reviews' in f.lower() or 'step' in f.lower():
            reason = "Product reviews kurulumunun eski versiyonlari"
        arc.append(f"- **`{f}`** ({size} B) - {reason}")
    arc.append("")

with open(os.path.join(base, "ARCHIVE_INVENTORY.md"), 'w', encoding='utf-8') as f:
    f.write('\n'.join(arc))

# === MIGRATION LOG ===
log = ["# Migration Log", "", f"**Tarih:** {datetime.now().strftime('%Y-%m-%d')}  ",
       "**Amac:** Production'a uygulanan/uygulanacak tum migrationlarin kronolojik ozeti.",
       "**Format:** `YYYYMMDDHHMMSS_name.sql` (Supabase CLI standardi)", "", "---", ""]

mig_files = sorted([f for f in os.listdir(mig_dir) if f.endswith('.sql') and re.match(r'^\d{14}_', f)])
by_year = {}
for f in mig_files:
    by_year.setdefault(f[:4], []).append(f)

log.append(f"**Toplam:** {len(mig_files)} migration, {len(by_year)} yil")
log.append("")

for yyyy in sorted(by_year.keys()):
    log.append(f"## {yyyy}")
    log.append(f"**{len(by_year[yyyy])} migration**")
    log.append("")
    log.append("| Tarih | Dosya | Boyut |")
    log.append("|---|---|---|")
    for f in by_year[yyyy]:
        size = os.path.getsize(os.path.join(mig_dir, f))
        size_kb = f"{size/1024:.1f}K" if size > 1024 else f"{size}B"
        date_part = f"{f[0:4]}-{f[4:6]}-{f[6:8]} {f[8:10]}:{f[10:12]}:{f[12:14]}"
        log.append(f"| {date_part} | `{f}` | {size_kb} |")
    log.append("")

with open(os.path.join(base, "MIGRATION_LOG.md"), 'w', encoding='utf-8') as f:
    f.write('\n'.join(log))

print(f"ARCHIVE_INVENTORY.md yazildi ({sum(1 for _ in open(os.path.join(base, 'ARCHIVE_INVENTORY.md'), encoding='utf-8'))} satir)")
print(f"MIGRATION_LOG.md yazildi ({len(mig_files)} migration, {len(by_year)} yil)")
