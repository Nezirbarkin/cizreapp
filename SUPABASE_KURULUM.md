# 🚀 CizreApp Supabase Kurulum Rehberi

## 📋 Hızlı Başlangıç

```
1️⃣ missing_tables.sql
2️⃣ rls_policies.sql
3️⃣ social_test_data.sql (İsteğe bağlı)
4️⃣ TESTING (Uygulamada test et)
```

---

## 🔧 ADIM 1: Eksik Tabloları Oluştur

**Dosya:** `missing_tables.sql`

### Yapılacaklar:
1. Supabase Dashboard'a git
   - https://app.supabase.com/
   - Projenizi seçin

2. SQL Editor'u aç
   - Sol menüden "SQL Editor"
   - "New Query" tıkla

3. Dosya içeriğini kopyala
   - `missing_tables.sql` açın (VS Code'da)
   - Tüm içeriği kopyala (Ctrl+A, Ctrl+C)

4. Supabase'e yapıştır
   - SQL Editor alanına yapıştır
   - "Run" butonuna tıkla (🎯 veya Ctrl+Enter)

### ✅ Başarılı İse:
```
✓ post_saves
✓ campaigns  
✓ coupons
✓ İlgili indexes

Mesaj: "Query executed successfully" göreceksin
```

### ❌ Hata İse:
```
Hata: "relation already exists"
→ Bu tablo zaten var, sorun yok

Hata: "column does not exist"
→ Supabase şemaları farklı olabilir
→ Bölüm altındaki 🐛 Sorun Giderme'yi gör
```

---

## 🔐 ADIM 2: RLS Politikalarını Kurulöştür

**Dosya:** `rls_policies.sql`

### Yapılacaklar:
1. Aynı SQL Editor'da yeni query aç
   - "New Query" tıkla

2. `rls_policies.sql` dosyasını kopyala

3. Supabase'e yapıştır ve çalıştır
   - "Run" butonuna tıkla

### ✅ Başarılı İse:

Sonunda bu sorguları göreceksin:
```
-- RLS durumunu kontrol et
SELECT 
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- Policy sayısını kontrol et
SELECT 
  schemaname,
  tablename,
  COUNT(*) as policy_count
FROM pg_policies
WHERE schemaname = 'public'
GROUP BY schemaname, tablename
ORDER BY tablename;
```

Bu sorgular çalıştırıldığında:
- ✅ 30+ tablo görünecek (hepsi `rowsecurity = true`)
- ✅ 80+ policy göreceğiz

### ❌ Hata İse:

```
ERROR: ... does not exist
```

**Çözüm:** 
→ Bölüm altındaki 🐛 Sorun Giderme'yi gör

---

## 📊 ADIM 3: Test Verisi Ekle (İsteğe Bağlı)

**Dosya:** `social_test_data.sql`

Uygulamada test yapmak için örnek veriler ekler.

### Yapılacaklar:
1. Yeni query aç
2. `social_test_data.sql` kopyala
3. Çalıştır

### ✅ Başarılı İse:
```
✓ 3 test kullanıcı
✓ 5 test gönderi
✓ 2 test story
✓ Takip ilişkileri
```

---

## 🧪 ADIM 4: Uygulamada Test Et

### Terminal'de:
```bash
cd c:/Users/lenovo/cizreapp
flutter clean
flutter pub get
flutter run
```

### Test Adımları:

#### 1️⃣ **Giriş Yap**
```
Email: test1@example.com
Şifre: Test@123
```

#### 2️⃣ **Profil Ekranını Aç**
- Bottom navigation > Profile (👤)
- Gönderiler görünüyor mu?

#### 3️⃣ **Avatar Yükle**
- "Edit Profile" tıkla
- Avatar seç
- ✅ Yükleniyor mu? (Loading spinner)
- ✅ Profil fotoğrafı değişti mi?

#### 4️⃣ **Kapak Fotoğrafı Yükle**
- Kapak fotoğrafı seç
- ✅ Kapak değişti mi?

#### 5️⃣ **Gönderi Oluştur**
- Social ekranında "Create Post" tıkla
- Başlık ve açıklama yaz
- Fotoğraf ekle
- Paylaş

#### 6️⃣ **Gönderi İşlemleri**
- ❤️ Beğen (Kırmızı olmalı)
- 💾 Kaydet (Kaydedildi mi?)
- 💬 Yorum Yap

#### 7️⃣ **Takip Et**
- Başka kullanıcının profil aç
- "Follow" tıkla

### Console'da Logları İzle:
```bash
flutter run -v
# Tüm işlemlerin loglarını göreceksin
```

---

## 🐛 Sorun Giderme

### ❌ "column ... does not exist" Hatası

**Nedeni:** Supabase tablolarınızda sütun isimleri farklı olabilir

**Çözüm:**
1. Supabase Dashboard > Table Editor
2. Hata veren tabloyu aç
3. Sütun isimlerini kontrol et
4. `rls_policies.sql` dosyasında:
   ```sql
   -- Yanlış:
   USING (user_id = auth.uid())
   
   -- Doğru (eğer sütun başka ise):
   USING (profile_id = auth.uid())
   -- veya
   USING (author_id = auth.uid())
   ```
5. Dosyayı düzelt ve tekrar çalıştır

### ❌ "relation ... does not exist" Hatası

**Nedeni:** Tablo yok

**Çözüm:**
1. `supabase_schema.sql` dosyasını çalıştır (varsa)
2. Eksik tabloları el ile oluştur:
   ```sql
   CREATE TABLE IF NOT EXISTS tablename (
     id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
     -- diğer sütunlar...
   );
   ```

### ❌ RLS Hatası: "new row violates row level security policy"

**Nedeni:** Politika çok katı veya yanlış

**Çözüm:**
1. Politikaları kontrol et:
   ```sql
   SELECT * FROM pg_policies 
   WHERE tablename = 'posts';
   ```

2. Sorunlu politikayı sil:
   ```sql
   DROP POLICY "policy_name" ON public.posts;
   ```

3. Yeni politika oluştur:
   ```sql
   CREATE POLICY "posts_select_policy"
   ON public.posts FOR SELECT
   TO public
   USING (is_active = true);
   ```

### ❌ Uygulamada "RLS Policy" Hatası

**Nedeni:** RLS politika uygulamayı engelliyor

**Çözüm:**
1. Supabase Dashboard > Authentication > Policies
2. Hata veren tabloyu bulun
3. Konsolda gördüğünüz hataya bakın
4. Politikayı düzelt

**Örnek:**
```
HINT: Check that the policy allows the INSERT...
```

→ INSERT politikası ekle:
```sql
CREATE POLICY "table_name_insert"
ON public.table_name FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());
```

---

## ✅ Kontrol Listesi

- [ ] Supabase hesabı var
- [ ] Proje oluşturdum
- [ ] `missing_tables.sql` çalıştırdım
- [ ] `rls_policies.sql` çalıştırdım
- [ ] `social_test_data.sql` çalıştırdım (isteğe bağlı)
- [ ] Flutter uygulamasını çalıştırdım
- [ ] Giriş yaptım
- [ ] Profil ekranını gördüm
- [ ] Avatar yükledim
- [ ] Kapak fotoğrafı yükledim
- [ ] Gönderi oluşturdum
- [ ] Beğeni tıkladım
- [ ] Kaydet tıkladım
- [ ] Takip ettim

---

## 📞 Hızlı Referans

| İşlem | Komut/Yol |
|------|-----------|
| **Supabase Dashboard** | https://app.supabase.com/ |
| **SQL Editor** | Dashboard > SQL Editor |
| **Tablo Editor** | Dashboard > Table Editor |
| **RLS Politikaları** | Dashboard > Table Editor > (Tablo) > Policies |
| **Storage Buckets** | Dashboard > Storage > Buckets |

---

## 🎯 Sırada Neler Var?

- ✅ Supabase veritabanı kurulumu
- ⏳ Admin Panel (Web) - www.cizreapp.com/admin
- ⏳ Satıcı Panel (Web) - www.cizreapp.com/satici
- ⏳ Bildirim Sistemi
- ⏳ Ödeme Entegrasyonu (iyzico)

---

## 💡 İpuçları

### Storage Buckets Oluşturma (İsteğe Bağlı)

Avatar ve kapak fotoğrafları için:

1. Dashboard > Storage
2. "Create New Bucket" tıkla
3. Bucket adı: `avatars` (Public seç)
4. Tekrar: `covers` (Public seç)

### RLS Politikaları Devre Dışı Bırakma (Geliştirme Sırasında)

```sql
ALTER TABLE public.posts DISABLE ROW LEVEL SECURITY;
```

⚠️ **UYARI:** Sadece geliştirme sırasında!

### Storage Politikaları Oluşturma

```sql
-- Avatars bucket
CREATE POLICY "Public Read"
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');

CREATE POLICY "User Upload"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'avatars'
  AND auth.uid()::text = (storage.foldername(name))[1]
);
```

---

## 📚 İlgili Dosyalar

- [`supabase_schema.sql`](supabase_schema.sql) - Veritabanı şeması
- [`missing_tables.sql`](missing_tables.sql) - Eksik tablolar
- [`rls_policies.sql`](rls_policies.sql) - RLS politikaları
- [`social_test_data.sql`](social_test_data.sql) - Test verileri
- [`docs/STORAGE_SETUP.md`](docs/STORAGE_SETUP.md) - Storage kurulumu
- [`docs/PROFIL_MODULU.md`](docs/PROFIL_MODULU.md) - Profil modülü dökümantasyonu

---

## 🎉 Tamamlanırsa

```
✅ Supabase veritabanı hazır
✅ RLS politikaları aktif
✅ Test verileri var
✅ Flutter uygulaması çalışıyor
✅ Profil modülü tam işlevsel
```

**Başarılar! 🚀**
