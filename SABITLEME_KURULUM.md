# Sabitleme (Pin/Sponsor) Özelliği Kurulum Kılavuzu

## Sorun
Admin panelinden sabitleme yapılıyor ancak hiçbir şey sabitlenmiyor.

## Sebep
`is_pinned` kolonları veritabanına eklenmemiş. Migration dosyası oluşturulmuş ancak Supabase'e henüz uygulanmamış.

## Çözüm Adımları

### 1. Supabase Dashboard'a Git
1. Tarayıcıda [https://supabase.com/dashboard](https://supabase.com/dashboard) adresini aç
2. Projenize giriş yapın

### 2. SQL Editor'ı Aç
1. Sol menüden **SQL Editor** sekmesine tıklayın
2. **New query** butonuna tıklayın

### 3. Migration SQL'ini Çalıştır
Aşağıdaki SQL kodunu kopyalayıp SQL Editor'a yapıştırın ve **Run** butonuna tıklayın:

```sql
-- is_pinned kolonu ekleme - Story, Product, Post, Shop tablolarına
-- Admin panelinden içerik sabitleme özelliği

-- Stories tablosuna is_pinned ekle
ALTER TABLE stories ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_stories_is_pinned ON stories (is_pinned) WHERE is_pinned = true;

-- Products tablosuna is_pinned ekle
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_products_is_pinned ON products (is_pinned) WHERE is_pinned = true;

-- Posts tablosuna is_pinned ekle
ALTER TABLE posts ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_posts_is_pinned ON posts (is_pinned) WHERE is_pinned = true;

-- Shops tablosuna is_pinned ekle
ALTER TABLE shops ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_shops_is_pinned ON shops (is_pinned) WHERE is_pinned = true;
```

### 4. Başarı Kontrolü
SQL çalıştıktan sonra şu mesajı görmelisiniz:
```
Success. No rows returned
```

### 5. Kolonların Eklendiğini Doğrula
Yeni bir query açıp aşağıdaki SQL'i çalıştırın:

```sql
-- is_pinned kolonlarını kontrol et
SELECT 
  table_name,
  column_name,
  data_type,
  column_default
FROM information_schema.columns 
WHERE column_name = 'is_pinned'
  AND table_schema = 'public'
ORDER BY table_name;
```

Şu 4 satırı görmelisiniz:
- posts | is_pinned | boolean | false
- products | is_pinned | boolean | false  
- shops | is_pinned | boolean | false
- stories | is_pinned | boolean | false

## Test Etme

### 1. Uygulamayı Yeniden Başlat
```bash
flutter run
```

### 2. Admin Panelinde Sabitleme Yap
1. Admin paneline gir
2. Herhangi bir Post/Story/Product üzerinde **3 nokta** menüsüne tıkla
3. "Sabitle" veya "Sabitlemeyi Kaldır" seçeneğine tıkla
4. Shop için: Dükkan kartına **uzun bas** (long press) -> "Sabitle/Sabitlemeyi Kaldır"

### 3. Sabitlemenin Çalıştığını Doğrula
- Sabitlediğinizde amber/altın renkli **"Sabitlendi"** rozeti görmelisiniz (admin panelde)
- Sabitlenen içerik listenin **en üstüne** gelmelidir
- Kullanıcı tarafında sabitlenen içerikte **"⭐ Sponsor"** rozeti görünmelidir

## Hata Durumunda

### Hata: "column is_pinned does not exist"
**Sebep**: Migration uygulanmamış  
**Çözüm**: Yukarıdaki SQL'i tekrar çalıştırın

### Hata: "permission denied"
**Sebep**: Yeterli yetki yok  
**Çözüm**: Supabase Dashboard'da proje sahibi hesabıyla giriş yapın

### Sabitleme çalışıyor ama görünmüyor
**Kontrol listesi**:
1. ✅ Migration uygulandı mı? (SQL Editor'da kontrol et)
2. ✅ Uygulamayı yeniden başlattın mı?
3. ✅ Admin panelde "Sabitlendi" rozeti görünüyor mu?
4. ✅ Model sınıflarında `isPinned` alanı var mı?

## Özellik Detayları

### Admin Paneli
- **Posts/Stories/Products**: PopupMenu (3 nokta) -> "Sabitle/Sabitlemeyi Kaldır"
- **Shops**: Long press -> Bottom sheet -> "Sabitle/Sabitlemeyi Kaldır"
- Sabitlenen kartlarda amber renkli "Sabitlendi" rozeti

### Kullanıcı Arayüzü
- Sabitlenen içerikler otomatik olarak **listelerin en üstünde** görünür
- Her sabitlenen içerikte **"⭐ Sponsor"** rozeti gösterilir
- Rozet rengi: `Colors.amber.shade700` (altın/sponsor rengi)

### Etkilenen Ekranlar
**Post Sponsor Badge:**
- Social ekranı (Twitter tarzı kartlar)
- Profil ekranı

**Story Sponsor Badge:**
- Market ekranı (compact view - yıldız ikonu)
- Social ekranı (full view - "Sponsor" yazısı)

**Product Sponsor Badge:**
- Ana ekran
- Shop detay
- İndirimli ürünler

**Shop Sponsor Badge:**
- Market ana ekranı
- Tüm dükkanlar
- Kategoriye göre dükkanlar

## Veritabanı Yapısı

Her tabloda:
- Kolon: `is_pinned BOOLEAN DEFAULT false`
- Index: `idx_{table}_is_pinned` (partial index, sadece `is_pinned = true` olanlar)

Sıralama:
```sql
ORDER BY is_pinned DESC, created_at DESC
```

Bu sayede:
1. Sabitlenenler en üstte (`is_pinned = true`)
2. Sonra normal içerikler (`is_pinned = false`)
3. Her grup kendi içinde tarih sırasına göre
