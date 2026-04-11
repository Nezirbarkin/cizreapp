# Supabase Storage Setup - Profil Modülü

## 🗂️ Storage Buckets Oluşturma

### 1. Avatars Bucket

Supabase Dashboard > Storage > New Bucket

```
Name: avatars
Public: ✓ (Enable public access)
```

### 2. Covers Bucket

```
Name: covers  
Public: ✓ (Enable public access)
```

## 🔐 Storage Policies

### Mevcut Policies Kontrol

Storage > avatars > Policies

Eğer "Allow authenticated upload" zaten varsa **silme**, aşağıdaki komutu çalıştırma.

### Avatars Bucket Policies

**1. Upload Policy (Eğer yoksa ekle)**

```sql
-- Önce mevcut policy'yi kontrol et
SELECT * FROM storage.policies WHERE bucket_id = 'avatars';

-- Eğer yoksa ekle:
CREATE POLICY "avatars_upload_policy"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'avatars');
```

**2. Public Read Policy**

```sql
-- Public okuma izni
CREATE POLICY "avatars_public_read"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'avatars');
```

**3. Update Policy**

```sql
-- Kendi dosyasını güncelleme
CREATE POLICY "avatars_update_own"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]);
```

**4. Delete Policy**

```sql
-- Kendi dosyasını silme
CREATE POLICY "avatars_delete_own"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]);
```

### Covers Bucket Policies

**1. Upload Policy**

```sql
-- Covers upload
CREATE POLICY "covers_upload_policy"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'covers');
```

**2. Public Read Policy**

```sql
-- Public okuma
CREATE POLICY "covers_public_read"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'covers');
```

**3. Update Policy**

```sql
-- Kendi dosyasını güncelleme
CREATE POLICY "covers_update_own"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'covers' AND auth.uid()::text = (storage.foldername(name))[1]);
```

**4. Delete Policy**

```sql
-- Kendi dosyasını silme
CREATE POLICY "covers_delete_own"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'covers' AND auth.uid()::text = (storage.foldername(name))[1]);
```

## ✅ Policy Kontrol

Storage bölümünde policies görünmeli:

### Avatars Bucket:
- ✓ avatars_upload_policy (INSERT)
- ✓ avatars_public_read (SELECT)
- ✓ avatars_update_own (UPDATE)
- ✓ avatars_delete_own (DELETE)

### Covers Bucket:
- ✓ covers_upload_policy (INSERT)
- ✓ covers_public_read (SELECT)
- ✓ covers_update_own (UPDATE)
- ✓ covers_delete_own (DELETE)

## 🧪 Test

### Upload Test

```dart
// Test avatar upload
final file = File('/path/to/image.jpg');
await Supabase.instance.client.storage
    .from('avatars')
    .upload('test.jpg', file);

// Test cover upload
await Supabase.instance.client.storage
    .from('covers')
    .upload('test-cover.jpg', file);
```

### Public URL Test

```dart
final avatarUrl = Supabase.instance.client.storage
    .from('avatars')
    .getPublicUrl('test.jpg');

print('Avatar URL: $avatarUrl');
// Tarayıcıda aç, görsel görünmeli
```

## ⚠️ Sorun Giderme

### "Policy already exists" Hatası

Bu hata, policy zaten varsa çıkar. İki seçenek:

**1. Mevcut Policy'yi Kullan**
```
✓ Hiçbir şey yapma, zaten ayarlanmış
```

**2. Policy'yi Güncelle**
```sql
-- Önce sil
DROP POLICY IF EXISTS "Allow authenticated upload" ON storage.objects;

-- Yeni isimle oluştur
CREATE POLICY "avatars_upload_policy" ...
```

### "Bucket does not exist" Hatası

```
❌ Bucket oluşturulmamış
✓ Storage > New Bucket > "avatars" oluştur
✓ Storage > New Bucket > "covers" oluştur
```

### "Permission denied" Hatası

```
❌ Policy eksik veya yanlış
✓ Yukarıdaki SQL komutlarını çalıştır
✓ Bucket'ların "Public" olduğundan emin ol
```

## 📊 Bucket Size Limits

Supabase Free Tier:
- Max file size: 50 MB
- Total storage: 1 GB

Avatar ve cover için yeterli!

## 🎯 Özet

1. ✅ 2 bucket oluştur (avatars, covers)
2. ✅ Her biri public olmalı
3. ✅ 4 policy ekle (INSERT, SELECT, UPDATE, DELETE)
4. ✅ Test et

**Artık profil ve kapak fotoğrafları yüklenebilir!** 📸✨
