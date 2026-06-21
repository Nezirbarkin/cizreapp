# PostgreSQL Kurulum Rehberi

## Admin PowerShell Açma

1. **Başlat** menüsüne sağ tıklayın
2. **"Windows PowerShell (Admin)"** veya **"Terminal (Admin)"** seçin
3. Açılan pencereye "Evet" tıklayın

## PostgreSQL Kurulumu

PowerShell'de şu komutu çalıştırın:

```powershell
choco install postgresql17 -y --no-progress
```

## Kurulum Sonrası

1. Kurulum tamamlandıktan sonra **yeni bir PowerShell penceresi** açın
2. pg_dump'ın çalıştığını doğrulayın:
   ```powershell
   pg_dump --version
   ```

## Yedek Alma Komutu

pg_dump çalıştıktan sonra şu komutla yedek alın:

```powershell
$env:PGPASSWORD = 'rupkkZOZGijJcKkC'
pg_dump -h aws-0-eu-central-1.pooler.supabase.com -p 5432 -U postgres.xsbukxkgtmdyickknqzf -d postgres -f supabase_backup_20260615.sql
```

## Önemli Notlar

- Şifre: `rupkkZOZGijJcKkC` (doğru mu kontrol edin)
- Yedek dosyası: `supabase_backup_20260615.sql`
- Kurulum ~500MB boyutunda, 5-10 dakika sürebilir
