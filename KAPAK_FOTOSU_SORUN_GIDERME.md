# 🔧 Kapak Fotoğrafı Değişmiyor - Sorun Giderme Rehberi

## 🔴 Tespit Edilen Sorun

Kapak fotoğrafı edit screen'de seçilse bile profil ekranında görmüyor.

### Olası Sebepler:

1. **RLS Policy Hatası** - Bucket'a yazma izni yok
2. **Upload Başarısız** - Storage error 403
3. **URL Caching** - Eski URL return ediliyor
4. **Profil Reload Sorun** - Navigator.pop(true) ama _loadProfile() çalışmıyor

---

## ✅ Çözüm Adımları

### Adım 1: Supabase RLS Policies Kontrol Edin

**Supabase Dashboard → SQL Editor**

```sql
-- 1. Bucket'ları kontrol et
SELECT name, public FROM storage.buckets 
WHERE name IN ('avatars', 'covers');

-- 2. RLS policies'leri kontrol et
SELECT * FROM pg_policies 
WHERE tablename = 'objects' 
AND schemaname = 'storage'
ORDER BY policyname;

-- 3. Güncel policies'leri ekle (eğer yoksa)
CREATE POLICY "Allow authenticated users to upload covers"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'covers' 
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Allow authenticated users to update covers"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'covers' 
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Public read covers"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'covers');
```

### Adım 2: Edit Screen'de Upload Log'u Kontrol Edin

Logcat/Console çıktısında şunları ararsınız:

```
✅ Kapak yüklenemde başarılı:
📤 Kapak fotoğrafı yükleniyor: /path/to/image
✅ Dosya yüklendi: cover_abc123-1705855200000.jpg
🔗 Public URL: https://...
✅ Profil güncellendi: {...}

❌ Hata durumunda:
❌ Kapak fotoğrafı yüklenemedi: StorageException (403)
❌ Kapak - Kullanıcı ID boş
```

---

### Adım 3: Cache Problem Çözmek

Firebase Storage'dan farklı olarak Supabase Storage cache header kullanan.

**Dosya Adı Unique Yap:**

```dart
// Şu an yapılan (cache problemi olabilir):
final fileName = 'cover_$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';

// Daha guarantee unique (Her upload için yeni dosya):
final timestamp = DateTime.now().millisecondsSinceEpoch;
final random = Random().nextInt(100000);
final fileName = 'cover_$userId-$timestamp-$random.jpg';
```

---

### Adım 4: Profil Screen'de URL Caching Kontrol

`profile_screen.dart`'ta Image.network() cache problem yaşayabilir.

```dart
// Önceki (cache problemi):
Image.network(coverUrl, fit: BoxFit.cover)

// Düzeltilmiş (cache bypass):
Image.network(
  coverUrl,
  fit: BoxFit.cover,
  cache: true,
  cacheHeight: 240,  // Explicit cache size
)
```

---

### Adım 5: Navigator.pop() Sonrası _loadProfile() Çağrılıyor mu?

`edit_profile_screen.dart`'ta kontrol edin:

```dart
Navigator.pop(context, true);  // true döndür

// profile_screen.dart'ta
if (result == true) {
  _loadProfile();  // Profili yenile
}
```

---

## 🧪 Test Prosedürü

### Test 1: Storage Bucket Kontrol
1. Supabase Dashboard → Storage
2. `covers` bucket var mı? ✅
3. Public mi? ✅

### Test 2: RLS Policies Kontrol
1. Supabase Dashboard → SQL Editor
2. storage_rls_fix.sql çalıştır
3. Policies oluşturuldu mu?

### Test 3: Upload Test
1. Flutter uygulaması çalıştır
2. Profil → Düzenle
3. Kapak seç
4. Konsol log'u kopyala

### Test 4: URL Test
1. Console'da URL'yi kopyala
2. Browser'da aç
3. Resim görünüyor mu?

---

## 🛠️ Kodda Yapılan Düzeltmeler

### profile_service.dart (uploadCoverPhoto):
```dart
✅ upsert: true → Aynı adlı dosya override
✅ cacheControl: '3600' → 1 saat cache
✅ .select() → Response döndür
✅ updated_at güncellemesi
```

### edit_profile_screen.dart (_saveProfile):
```dart
✅ Detaylı logging
✅ Upload response kontrol
✅ Profil update başarı kontrol
✅ Navigator.pop(context, true) → Profil reload
```

### profile_screen.dart (_loadProfile):
```dart
✅ if (result == true) _loadProfile()
✅ Parallel loading (Future.wait)
✅ Batch queries
```

---

## 🔍 Detaylı Kontrol Listesi

- [ ] Supabase'de `avatars` bucket var
- [ ] Supabase'de `covers` bucket var
- [ ] İkisi de Public ayarında
- [ ] RLS policies oluşturuldu (storage_rls_fix.sql)
- [ ] profiles tablosunda `cover_url` kolonu var
- [ ] profiles tablosunda `avatar_url` kolonu var
- [ ] Edit screen'de kapak seçebiliyorsunuz
- [ ] Console'da hata mesajı yok (403 vs)
- [ ] Edit screen'de kapak preview güncelleniyor
- [ ] Navigator.pop(context, true) çağrılıyor
- [ ] Profil screen'de _loadProfile() çalışıyor
- [ ] URL browserda açılıyor

---

## 📱 Hızlı Çözüm

**Eğer hiçbir şey çalışmazsa:**

1. Flutter uygulaması kapatın
2. `flutter clean` çalıştırın
3. `flutter pub get` çalıştırın
4. Supabase Storage bucket'ları yeniden oluşturun
5. SQL script'i yeniden çalıştırın
6. `flutter run` baştan başlatın

---

## 📞 Support

Eğer hala çalışmazsa lütfen bildirin:
- Console log çıktısını kopyalayın
- 403 hatası var mı?
- RLS policy error var mı?
- Storage bucket URL doğru mu?
