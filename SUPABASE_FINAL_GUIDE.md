# 🚀 CizreApp Supabase Kurulum - Final Rehber

## ⚡ HIZLI BAŞLANGÇ (5 DAKİKA)

Supabase'e SQL dosyalarını sırayla yapıştırıp çalıştırın:

```
1. supabase_schema.sql (tablolar oluştur)
2. missing_tables.sql (eksik tablolar)
3. rls_clean_install.sql (RLS politikaları)
4. supabase_security_fixes.sql (güvenlik düzeltmeleri)
5. social_test_data.sql (test verileri - isteğe bağlı)
6. Dashboard > Password Protection enable et
```

---

## 📋 ADIM ADIM KURULUM

### ADIM 1: supabase_schema.sql Çalıştır

```bash
# Supabase Dashboard > SQL Editor > New Query

# İşlem:
1. supabase_schema.sql dosyasını aç
2. Tüm içeriği kopyala (Ctrl+A, Ctrl+C)
3. SQL Editor alanına yapıştır
4. RUN butonuna tıkla (veya Ctrl+Enter)

# ✅ Başarılı İse:
SUCCESS: ... policy created
SUCCESS: ... table created
No errors
```

### ADIM 2: missing_tables.sql Çalıştır

```bash
# Supabase Dashboard > SQL Editor > New Query

# İşlem:
1. missing_tables.sql dosyasını aç
2. Tüm içeriği kopyala
3. SQL Editor alanına yapıştır
4. RUN tıkla

# ✅ Başarılı İse:
3 tablolar oluşturuldu:
- post_saves
- campaigns
- coupons

CREATE TABLE: post_saves
CREATE TABLE: campaigns
CREATE TABLE: coupons
```

### ADIM 3: rls_clean_install.sql Çalıştır

```bash
# Supabase Dashboard > SQL Editor > New Query

# İşlem:
1. rls_clean_install.sql dosyasını aç
2. Tüm içeriği kopyala
3. SQL Editor alanına yapıştır
4. RUN tıkla

# ✅ Başarılı İse:
70+ policies created
0 errors

Konsolda tablolar ve policy sayısı göreceksiniz
```

### ADIM 4: supabase_security_fixes.sql Çalıştır

```bash
# Supabase Dashboard > SQL Editor > New Query

# İşlem:
1. supabase_security_fixes.sql dosyasını aç
2. Tüm içeriği kopyala
3. SQL Editor alanına yapıştır
4. RUN tıkla

# ✅ Başarılı İse:
4 fonksiyon güncellendi
8 trigger oluşturuldu
0 errors
```

### ADIM 5: social_test_data.sql Çalıştır (İsteğe Bağlı)

```bash
# Supabase Dashboard > SQL Editor > New Query

# İşlem:
1. social_test_data.sql dosyasını aç
2. Tüm içeriği kopyala
3. SQL Editor alanına yapıştır
4. RUN tıkla

# ✅ Başarılı İse:
Test verileri eklendi:
- 3 kullanıcı
- 5 gönderi
- 2 story
- Takip ilişkileri
- Beğeniler

# NOT: Bu adım opsiyonel
# Uygulamada anında test edebilirsiniz
```

### ADIM 6: Password Protection Aktif Et

```bash
# Supabase Dashboard (SQL değil!)

# İşlem:
1. Supabase Dashboard > Authentication
2. Policies sekmesine tıkla
3. "Password Strength" bölümünü bul
4. "Leaked Password Protection" ✅ Enable
5. "Block leaked passwords" ✅ Seç
6. "Save" tıkla

# ⏱️ Süre: 30 saniye
# Bu adım opsiyonel ama önerilir
```

---

## 🧪 DOĞRULAMA

### Supabase Dashboard'da Kontrol Et

```bash
# Supabase Dashboard > Table Editor

✅ Kontrol Listesi:

1. Tablolar mı var?
   - profiles
   - posts
   - post_likes
   - post_comments
   - post_saves ← YENİ
   - shops
   - products
   - orders
   - campaigns ← YENİ
   - coupons ← YENİ
   - ve diğer 15+ tablo

2. RLS aktif mi?
   Supabase Dashboard > Table Editor > (Tablo) > Auth
   "Row Level Security" ✅ ON
   (Her tablo için kontrol et)

3. Policies var mı?
   Supabase Dashboard > Table Editor > (Tablo) > Policies
   20+ tablo > 3-5 policy her birinde

4. Trigger'lar var mı?
   Supabase Dashboard > Table Editor > (Tablo) > Actions
   Trigger'ları görebilirsiniz
```

### SQL ile Doğrula

```sql
-- RLS aktif mi?
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY tablename;
-- Sonuç: Hepsi "true" ✅

-- Kaç policy var?
SELECT tablename, COUNT(*) 
FROM pg_policies 
WHERE schemaname = 'public'
GROUP BY tablename
ORDER BY tablename;
-- Sonuç: 20+ tablo, 70+ policy ✅

-- Fonksiyonlar güncellendi mi?
SELECT proname, prosecdef, proconfig
FROM pg_proc
WHERE proname LIKE 'update_%'
ORDER BY proname;
-- Sonuç: search_path = 'public' ✅
```

---

## 🚀 FLUTTER UYGULAMASINI ÇALIŞTIR

```bash
# Terminal'de:
cd c:/Users/lenovo/cizreapp

# Temizle ve yenile
flutter clean
flutter pub get

# Çalıştır
flutter run

# Eğer cihaz seçimi sornarsa:
# Chrome (web) veya Android emülatörü seçin
```

---

## 🧪 UYGULAMA TEST SENARYOSU

### Test Kullanıcı Hesapları

```
Email: test1@example.com
Şifre: Test@123

Email: test2@example.com
Şifre: Test@123

Email: test3@example.com
Şifre: Test@123
```

### Test Adımları

```
1️⃣ GİRİŞ YAP
   - test1@example.com ile giriş yap
   - ✅ Profil ekranı açılmalı

2️⃣ PROFIL EKLEYİCİ
   - Edit Profile tıkla
   - Avatar seç (resim ekle)
   - Kapak fotoğrafı seç
   - Save tıkla
   - ✅ Resimler yüklenmelidir

3️⃣ GÖNDERI PAYLAŞ
   - Social ekranına git
   - "Create Post" tıkla
   - Başlık ve açıklama yaz
   - Resim ekle
   - Paylaş tıkla
   - ✅ Gönderi listelenmeli

4️⃣ BEĞEN VE KAYDET
   - Bir gönderiye ❤️ tıkla
   - ✅ Kırmızı olmalı
   - Bir gönderiye 💾 tıkla
   - ✅ Kayıtlılar sekmesinde görünmeli

5️⃣ YORUM YAP
   - Bir gönderiye 💬 tıkla
   - Yorum yaz
   - Gönder tıkla
   - ✅ Yorum listelenmeli

6️⃣ TAKIP ET
   - Başka kullanıcının profil aç
   - Follow tıkla
   - ✅ Takip ettiler listesinde görünmeli

7️⃣ SEPETE EKLE
   - Market ekranı aç
   - Bir ürüne tıkla
   - "Add to Cart" tıkla
   - ✅ Sepet güncellenmeli

8️⃣ SİPARİŞ VER
   - Cart ekranına git
   - Checkout tıkla
   - Adres seç/ekle
   - "Place Order" tıkla
   - ✅ Sipariş oluşturulmalı

9️⃣ MESAJ GÖNDER
   - Chat ekranı aç
   - Yeni konuşma başlat
   - Kullanıcı seç
   - Mesaj yaz
   - Gönder tıkla
   - ✅ Mesaj görünmeli
```

---

## 🔍 CONSOLE LOGLARINI İZLE

```bash
# Terminal'de flutter run açıkken Ctrl+Shift+D (DevTools)
# veya suanki terminalde logları izle

# Loglar göreceksiniz:
🔍 Fetching posts...
✅ 5 posts loaded
❤️ Post liked!
💾 Post saved!
...

# ❌ Eğer hata görürseniz:
ERROR: RLS policy violation
ERROR: column does not exist
ERROR: permission denied

# Çözüm: Supabase Linter'ı kontrol et
```

---

## 🐛 SORUN GİDERME

### ❌ "RLS policy violation"

```
Neden: Kullanıcı veri okuma/yazma izni yok

Çözüm:
1. Supabase Dashboard > Table Editor
2. Hata veren tabloyu aç
3. "Auth" sekmesine git
4. Policy'leri kontrol et
5. SELECT policy var mı?
6. Kullanıcının role'ü doğru mu? (customer/seller/admin)
```

### ❌ "column does not exist"

```
Neden: Sütun adı yanlış

Çözüm:
1. check_tables.sql dosyasını çalıştır
2. Doğru sütun adlarını göreceksin
3. SQL'i düzelt
4. Tekrar çalıştır
```

### ❌ "connection refused"

```
Neden: Supabase URL/key yanlış

Çözüm:
1. lib/main.dart dosyasını aç
2. Supabase URL'ini kontrol et
3. Supabase Anonymous Key'i kontrol et
4. Supabase Dashboard > Settings > API
5. Doğru değerleri kopyala
6. main.dart'ta güncelle
7. flutter run yeniden çalıştır
```

### ❌ "policy ... already exists"

```
Neden: Politika zaten var

Çözüm:
rls_clean_install.sql kullan
(Bu dosya eski politikaları siler)
```

---

## 📱 UYGULAMADA GERÇEK VERİ GÖRÜNTÜLEMEK

### Senaryo 1: Test Verileriyle (Hızlı)

```
1. social_test_data.sql çalıştır
2. 3 test kullanıcısı + verileri eklenir
3. App'ı aç
4. test1@example.com ile giriş yap
5. Hemen gönderiler görünür ✅
```

### Senaryo 2: Kendi Verileriyle (Normal)

```
1. App'ı aç
2. Kayıt ol ve giriş yap
3. Profil düzenle
4. Gönderi paylaş
5. Beğen, yorum yap, takip et
6. Senaryo 1'deki tüm işlemler
```

---

## 🎯 BITTIKTEN SONRA

### ✅ Başarılı Kurulum İşaretleri:

```
✅ Hiç hata yok
✅ 20+ tablo var
✅ 70+ policy aktif
✅ Test verileri yükleniyor/yüklendi
✅ App çalışıyor ve veri gösteriyor
✅ Profil, gönderiler, beğeniler çalışıyor
✅ Sepete ekleme, sipariş verme çalışıyor
✅ Mesajlaşma çalışıyor
```

### 📊 Uygulanacak Sonraki Adımlar:

```
1. Satıcı Panel (Web) - www.cizreapp.com/satici
2. Admin Panel (Web) - www.cizreapp.com/admin
3. Push Notifications (Opsiyonel)
4. iyzico Ödeme Entegrasyonu (Opsiyonel)
5. Deployment (Production)
```

---

## 📞 DESTEK

### Hata Alırsanız:

1. **Tam hata mesajını kopyala**
2. **Hangi adımda hata aldığını söyle**
3. **Supabase Dashboard > SQL Editor > Logs'ta bak**
4. **Supabase Docs: https://supabase.com/docs**

### Kontrol Sırasında:

- `check_tables.sql` - Tüm tabloları ve sütunları listele
- Supabase Dashboard - Visual kontrol
- SQL Linter - Sorunları bul
- Flutter Logs - App hataları

---

## 🎉 BAŞARILI KURULUM!

```
Eğer buraya geldiyseniz ve hiç hata yoksa:

🎊 TEBRİKLER! 🎊

CizreApp Supabase kurulumu tamamlandı!

Artık:
✅ Profil modülü çalışıyor
✅ Sosyal medya özellikleri aktif
✅ Market sistemi çalışıyor
✅ Alışveriş ve sipariş verme mümkün
✅ Mesajlaşma aktif
✅ Tüm veriler gerçek Supabase'den geliyor
✅ Güvenlik politikaları etkin
✅ Production hazır!

Sırada ne var?
→ Satıcı Panel
→ Admin Panel
→ Ödeme Entegrasyonu
→ Push Notifications
→ Deployment

Hepsi aynı kalitede yapılacak! 🚀
```

---

## 📚 Dosyalar Referansı

| Dosya | Satırlar | Amaç |
|-------|---------|------|
| [`supabase_schema.sql`](../supabase_schema.sql) | 570 | Veritabanı şeması (tabloları, indexleri, triggerleri oluşturur) |
| [`missing_tables.sql`](../missing_tables.sql) | 50 | Eksik 3 tabloyu ekler |
| [`rls_clean_install.sql`](../rls_clean_install.sql) | 200 | 70+ RLS politikasını temiz kurar |
| [`supabase_security_fixes.sql`](../supabase_security_fixes.sql) | 180 | Güvenlik düzeltmeleri (fonksiyonlar, triggers) |
| [`social_test_data.sql`](../social_test_data.sql) | 100 | Test verileri (3 kullanıcı, postlar, storyler) |
| [`check_tables.sql`](../check_tables.sql) | 30 | Tüm tabloları listele (kontrol için) |
| [`SUPABASE_KURULUM.md`](../SUPABASE_KURULUM.md) | 300 | Bu dosya (kurulum rehberi) |

---

**Başarılar! 🚀 Sorularınız varsa, hata alırsanız hemen bana yazın!**
