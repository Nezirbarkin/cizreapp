# Supabase Veritabanı Şifresini Bulma

## Adım adım şifre bulma:

1. [Supabase Dashboard](https://supabase.com/dashboard) adresine gidin
2. **"CizreApp"** projenizi seçin
3. Sol menüden **"Settings"** (Ayarlar) sekmesine tıklayın
4. Alt menüden **"Database"** seçeneğine tıklayın
5. **"Connection string"** bölümünü bulun
6. **"URI"** sekmesine tıklayın - şöyle bir format göreceksiniz:

```
postgresql://postgres.xsbukxkgtmdyickknqzf:[ŞİFRE]@aws-0-eu-central-1.pooler.supabase.com:5432/postgres
```

7. Köşeli parantez içindeki **[ŞİFRE]** sizin veritabanı şifrenizdir

## Alternatif: Direct Connection sekmesi

- **"Direct Connection"** sekmesinde de şifreyi görebilirsiniz
- **"Database password"** alanı şifrenizi gösterir

## Önemli notlar:

- Şifreyi ilk kez oluşturduysanız, bunu hatırlamanız gerekebilir
- Şifreyi unuttuysanız: **"Reset password"** butonu ile sıfırlayabilirsiniz
- Şifre sıfırlamak 2-3 dakika sürebilir
