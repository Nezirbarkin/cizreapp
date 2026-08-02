import os, re, sys
sys.stdout.reconfigure(encoding='utf-8')
from datetime import datetime

base = r"C:\Users\lenovo\cizreapp\supabase"
mig_dir = os.path.join(base, "migrations")
mig_files = sorted([f for f in os.listdir(mig_dir) if f.endswith('.sql') and re.match(r'^\d{14}_', f)])

patterns = {
    'TABLE': re.compile(r'CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+(?:public\.)?["\']?(\w+)["\']?', re.IGNORECASE),
    'FUNCTION': re.compile(r'CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+(?:public\.)?["\']?(\w+)["\']?', re.IGNORECASE),
    'VIEW': re.compile(r'CREATE(?:\s+OR\s+REPLACE)?\s+VIEW\s+(?:public\.)?["\']?(\w+)["\']?', re.IGNORECASE),
    'TRIGGER': re.compile(r'CREATE\s+TRIGGER\s+["\']?(\w+)["\']?', re.IGNORECASE),
    'POLICY': re.compile(r'CREATE\s+POLICY\s+["\']?(\w+)["\']?', re.IGNORECASE),
    'INDEX': re.compile(r'CREATE(?:\s+UNIQUE)?\s+INDEX(?:\s+IF\s+NOT\s+EXISTS)?\s+["\']?(\w+)["\']?', re.IGNORECASE),
}

schema_objects = {}
for f in mig_files:
    try:
        with open(os.path.join(mig_dir, f), 'r', encoding='utf-8', errors='ignore') as fp:
            content = fp.read()
        for ptype, pat in patterns.items():
            for m in pat.finditer(content):
                obj = m.group(1)
                if obj.lower() in ('if', 'exists', 'or', 'replace', 'public', 'schema', 'on'):
                    continue
                schema_objects.setdefault(obj, []).append(ptype)
    except: pass

# Sınıfla
tables = {k: v for k, v in schema_objects.items() if 'TABLE' in v}
funcs = {k: v for k, v in schema_objects.items() if 'FUNCTION' in v and 'TABLE' not in v}
views = {k: v for k, v in schema_objects.items() if 'VIEW' in v and 'TABLE' not in v}
triggers = {k: v for k, v in schema_objects.items() if 'TRIGGER' in v}
policies = {k: v for k, v in schema_objects.items() if 'POLICY' in v}

out = []
out.append("# Supabase Sema Indeksi")
out.append("")
out.append(f"**Tarih:** {datetime.now().strftime('%Y-%m-%d')}  ")
out.append("**Kaynak:** `supabase/migrations/` altindaki SQL dosyalarinda tanimlanan objelerin otomatik cikarimi.")
out.append(f"**Toplam migration:** {len(mig_files)}")
out.append("")
out.append("---")
out.append("")

# Tablolar
out.append(f"## TABLOLAR ({len(tables)})")
out.append("")
out.append("| Tablo | Ilk Tanim |")
out.append("|---|---|")
for t in sorted(tables.keys()):
    out.append(f"| `{t}` | (birden fazla migration) |")
out.append("")

# Fonksiyonlar
out.append(f"## FONKSIYONLAR / RPC'LER ({len(funcs)})")
out.append("")
out.append("| Fonksiyon |")
out.append("|---|")
for fn in sorted(funcs.keys()):
    out.append(f"| `{fn}` |")
out.append("")

# View'lar
out.append(f"## VIEW'LAR ({len(views)})")
out.append("")
for v in sorted(views.keys()):
    out.append(f"- `{v}`")
out.append("")

# Trigger'lar
out.append(f"## TRIGGER'LAR ({len(triggers)})")
out.append("")
for t in sorted(triggers.keys()):
    out.append(f"- `{t}`")
out.append("")

# Policy'ler
out.append(f"## RLS POLICY'LER ({len(policies)})")
out.append("")
out.append(f"**Toplam:** {len(policies)} policy")
out.append("")
out.append("Not: Policy'ler tablo bazinda migration dosyalarinda tanimli. Detay icin ilgili migration dosyasina bakin.")
out.append("")

# Storage bucket
bucket_pat = re.compile(r'INSERT\s+INTO\s+storage\.buckets[^)]*\(\s*[\'"](\w+)[\'"]', re.IGNORECASE)
buckets = set()
for f in mig_files:
    try:
        with open(os.path.join(mig_dir, f), 'r', encoding='utf-8', errors='ignore') as fp:
            for m in bucket_pat.finditer(fp.read()):
                buckets.add(m.group(1))
    except: pass

if buckets:
    out.append(f"## STORAGE BUCKET'LAR ({len(buckets)})")
    out.append("")
    for b in sorted(buckets):
        out.append(f"- `{b}`")
    out.append("")

out.append("---")
out.append("")
out.append("**Guncelleme:** Bu dosya otomatik uretilir. Yeniden olusturmak icin: `python plans/scripts/build_schema_index.py`")

with open(os.path.join(base, "SCHEMA_INDEX.md"), 'w', encoding='utf-8') as f:
    f.write('\n'.join(out))

print(f"SCHEMA_INDEX.md yazildi")
print(f"  Tablolar: {len(tables)}")
print(f"  Fonksiyonlar: {len(funcs)}")
print(f"  View'lar: {len(views)}")
print(f"  Trigger'lar: {len(triggers)}")
print(f"  Policy'ler: {len(policies)}")
print(f"  Bucket'lar: {len(buckets)}")
