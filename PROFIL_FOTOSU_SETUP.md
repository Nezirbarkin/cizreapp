# 🖼️ Profil & Kapak Fotoğrafı Setup Rehberi

## ⚠️ Sorun: Profil ve kapak fotoğrafı değişmiyor

Supabase Storage bucket'ları kurulmamış olabilir. Aşağıdaki adımları takip edin:

## 🔧 Supabase Setup

### 1. **Storage Bucket'ları Oluşturma**

Supabase Dashboard → Storage bölümüne gidin ve şu bucket'ları oluşturun:

#### **Bucket 1: `avatars`**
```
- Bucket ismi: avatars
- Erişim: Public
- File size limit: 10 MB
```

#### **Bucket 2: `covers`**
```
- Bucket ismi: covers
- Erişim: Public
- File size limit: 50 MB
```

### 2. **Folder Yapısı (Opsiyonel ama Önerilen)**

`avatars` bucket'ında:
```
avatars/
├── 2024/
│   ├── 01/
│   └── 02/
└── ...
```

`covers` bucket'ında:
```
covers/
├── 2024/
│   ├── 01/
│   └── 02/
└── ...
```

### 3. **RLS Policies Ekleme**

#### **Avatars Bucket için RLS**

```sql
-- Policy: Kullanıcılar kendi avatar'larını upload edebilir
CREATE POLICY "Users can upload their own avatars" ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars' 
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Policy: Herkes avatar'ları görebilir
CREATE POLICY "Public read access to avatars" ON storage.objects
  FOR SELECT
  USING (bucket_id = 'avatars');

-- Policy: Kullanıcılar kendi avatar'larını güncelleyebilir/silebilir
CREATE POLICY "Users can update/delete their own avatars" ON storage.objects
  FOR UPDATE, DELETE
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
```

#### **Covers Bucket için RLS**

```sql
-- Policy: Kullanıcılar kendi cover'larını upload edebilir
CREATE POLICY "Users can upload their own covers" ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'covers'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Policy: Herkes cover'ları görebilir
CREATE POLICY "Public read access to covers" ON storage.objects
  FOR SELECT
  USING (bucket_id = 'covers');

-- Policy: Kullanıcılar kendi cover'larını güncelleyebilir/silebilir
CREATE POLICY "Users can update/delete their own covers" ON storage.objects
  FOR UPDATE, DELETE
  USING (
    bucket_id = 'covers'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
```

### 4. **Dosya Adlandırma Kuralı**

Upload işleminde dosya adı otomatik oluşturuluyor:

```dart
// Avatar örneği:
final fileName = 'avatar_$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';
// Sonuç: avatar_abc123-1705855200000.jpg

// Cover örneği:
final fileName = 'cover_$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';
// Sonuç: cover_abc123-1705855200000.jpg
```

### 5. **Test Etme Adımları**

1. **Flutter uygulamasını çalıştırın**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

2. **Profil ekranına gidin**
   - Bottom navigation → Profil

3. **"Profili Düzenle" tıklayın**
   - Edit profile screen açılır

4. **Avatar değiştiğini seçin**
   - Kamera ikonuna tıklayın
   - Galeriden fotoğraf seçin
   - Görselin değiştiğini kontrol edin (local preview)

5. **Kapak fotoğrafını değiştiğini seçin**
   - Kapak bölümünde kamera ikonuna tıklayın
   - Galeriden fotoğraf seçin

6. **"Değişiklikleri Kaydet" tıklayın**
   - SnackBar mesajında detaylı bilgi gösterilir
   - Profil ekranına geri döner

7. **Profil ekranında değişiklikleri kontrol edin**
   - Avatar değişmişse ✅
   - Kapak fotoğrafı değişmişse ✅

## 📋 Konsol Çıktılarını Kontrol Edin

Xcode Console veya Android Studio Logcat'te şu mesajları ararsınız:

### ✅ Başarılı olması durumunda:
```
📤 Avatar yükleniyor: /path/to/image.jpg
✅ Dosya yüklendi: avatar_abc123-1705855200000.jpg
🔗 Public URL: https://...bucket.com/avatars/avatar_abc123-1705855200000.jpg
✅ Profil güncellendi: {...}
✅ Avatar yükleniyor...
✅ Avatar URL: https://...
```

### ❌ Hata durumunda:
```
❌ Profil ve kapak fotoğrafı değişmiyor
❌ Kapak fotoğrafı yüklenemedi: [HATA MESAJI]
❌ Avatar - Kullanıcı ID boş
```

## 🆘 Sorun Giderme

### Sorun 1: "403 Forbidden" hatası
**Çözüm:** RLS policies'leri kontrol edin
```sql
-- Supabase Dashboard → SQL Editor
-- Yukarıdaki RLS kodlarını çalıştırın
```

### Sorun 2: Storage bucket'ı bulunamıyor
**Çözüm:** Bucket'ların doğru isimle oluşturulduğunu kontrol edin
- `avatars` (küçük harf)
- `covers` (küçük harf)

### Sorun 3: URL oluşturulamıyor
**Çözüm:** Bucket'ın erişim ayarlarını kontrol edin
```
Supabase Dashboard → Storage → avatars/covers
→ Bucket Access Policy
→ "Public" seçili mi kontrol edin
```

### Sorun 4: Yükleme başarılı ama profilde görünmüyor
**Çözüm:** Profil ekranındaki `_loadProfile()` çağrısını kontrol edin
- Navigator.pop(context, true) sonrası yenileniyor
- Cache'i temizleyin veya app'ı restart edin

## 📝 Dosya Boyutu Limitleri

```
Avatars:
- Max: 10 MB
- Önerilen: 2-3 MB (compression ile)

Covers:
- Max: 50 MB  
- Önerilen: 5-10 MB (compression ile)
```

## 🎨 Tavsiye Edilen Boyutlar

```
Avatar:
- Genellik: 400x400 px
- Format: JPG/PNG
- Aspect Ratio: 1:1 (kare)

Cover:
- Genellik: 1200x600 px
- Format: JPG/PNG
- Aspect Ratio: 2:1 (geniş)
```

## ✨ Kodda Yapılan İyileştirmeler

### profile_service.dart:
✅ Better logging (📤, ✅, 🔗, ❌)
✅ `upsert: true` (aynı adlı dosyayı değiştirir)
✅ `cacheControl: '3600'` (cache header)
✅ `.select()` ile response döndür
✅ `updated_at` timestamp güncellemesi

### edit_profile_screen.dart:
✅ Hata handling iyileştirildi
✅ Detaylı SnackBar mesajları
✅ Upload durumu gösteriliyor
✅ Return value kontrol edildiği

## 🧪 Çabuk Test Komutu

```bash
# Terminal'de:
flutter run -v

# Çıktıda "📤 Avatar yükleniyor:" ararsınız
# Başarılı olursa "✅ Profil güncellendi:" görürsünüz
```

---

**Tüm adımları tamamladıktan sonra uygulamayı test edin!** 🚀
