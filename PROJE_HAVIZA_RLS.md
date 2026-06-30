# PROJE_HAVIZA_RLS

Son güncelleme: 2026-06-29  
Project Ref: `xsbukxkgtmdyickknqzf`

## 1) Genel RLS Durumu

Projede RLS yoğun kullanılıyor.  
Özellikle şu alanlarda politika seti kapsamlı:

- `profiles`
- `orders`, `order_items`
- `shops`, `products`
- `messages`, `conversations`
- `groups` ve `group_*`
- `notifications`
- `ai_*`
- `storage.objects`

## 2) Sık Kullanılan Yetki Pattern’leri

- `auth.uid()` ile sahiplik kontrolü
- `auth_is_admin()` / `is_admin()`
- Profil rolü kontrolü (`profiles.role = 'admin'`)
- Grup fonksiyonları:
  - `is_group_member(group_id, auth.uid())`
  - `is_group_admin(group_id, auth.uid())`

## 3) Domain Bazlı Özet

### 3.1 Profil / Kullanıcı
- Kullanıcı kendi profilini update edebilir.
- Admin profiller üzerinde geniş yetkiye sahip.
- Bildirim ve tercih tablolarında çoğunlukla “kendi kaydını gör/güncelle” modeli var.

### 3.2 Ürün / Mağaza
- Satıcı kendi mağazasının ürünlerinde insert/update/delete yapabilir.
- Admin override yetkisi bulunan policy’ler mevcut.
- Public/anon için görünürlük politikalı alanlar var (özellikle select policy’leri).

### 3.3 Sipariş
- Müşteri kendi siparişlerini görür.
- Satıcı kendi mağazasına ait siparişleri görür.
- Admin daha geniş görünürlük ve bazı durumlarda update/delete yetkisi alır.

### 3.4 Mesajlaşma
- 1-1 mesajlarda konuşma katılımcılığına bağlı görünürlük.
- Grup mesajlarında üyelik/adminlik koşullarına bağlı işlem.

### 3.5 AI
- `ai_conversations`, `ai_messages`, `ai_daily_usage` için kullanıcı sahipliği merkezli policy’ler.
- Admin için full/manage policy’leri de mevcut.
- `ai_settings` tarafında admin ve/veya authenticated temelli yazma policy’leri bulunuyor (kritik kontrol noktası).

### 3.6 Storage
- Bucket bazlı policy yaklaşımı var (`avatars`, `products`, `posts`, `stories`, `ai-uploads`, `ai-generated` vb.).
- Bazı bucket’larda public select + geniş insert/update/delete policy’leri mevcut; düzenli audit edilmeli.

## 4) Risk / Audit Checklist

- Çok geniş (`public` rolüne açık) write policy var mı?
- `WITH CHECK` sahiplik doğrulaması düzgün mü?
- Admin kontrolü sadece JWT role’a mı bağlı, yoksa `profiles` doğrulaması da var mı?
- Storage bucket policy’lerinde gereksiz anon write var mı?
- Aynı tabloda çakışan/duplicate policy var mı?

## 5) Önerilen Rutin

- Her migration sonrası RLS diff kontrolü
- Aylık policy audit
- Kritik tablolar için test senaryoları:
  - Owner erişimi
  - Non-owner erişim engeli
  - Admin override
  - Anon erişim sınırları