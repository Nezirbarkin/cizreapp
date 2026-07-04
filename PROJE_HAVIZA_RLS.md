# PROJE_HAVIZA_RLS

Son güncelleme: 2026-07-04
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

## 2) Sık Kullanılan Yetki Pattern'leri

- `auth.uid()` ile sahiplik kontrolü
- `auth_is_admin()` / `is_admin()` (bkz. Kritik Not 2.1)
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

### 4.1 Kritik Güvenlik Notları (2026-07-02 güncelleme)

#### 4.1.1 `is_admin()` vs `auth_is_admin()` — Yetki Farkı
İki fonksiyon aynı mantığı taşır (`profiles.role = 'admin'` kontrolü) ama **EXECUTE yetkileri farklıdır**:

| Fonksiyon | `SECURITY DEFINER` | `authenticated` EXECUTE | `anon` EXECUTE | Kullanım |
|-----------|:---:|:---:|:---:|---|
| `is_admin()` | ✅ Evet | ⚠️ **Elle eklenmeli** | ⚠️ **Elle iptal edilmeli** | RLS policy'ler (profiles, ai_settings, vb.) |
| `auth_is_admin()` | ❌ Hayır (STABLE) | ✅ Varsayılan | ✅ Varsayılan | Bazı legacy policy'ler |

**Neden önemli:** `is_admin()` SECURITY DEFINER olduğu için postgres rolüne düşer ve profiller tablosunu RLS'siz okur — bu doğru davranış. Ancak `CREATE OR REPLACE FUNCTION` sonrası GRANT'ler KORUNMAZ. Migration'larda `DROP FUNCTION ... CASCADE` + `CREATE FUNCTION` yapıldığında `GRANT EXECUTE` ayrıca verilmezse `authenticated` rolü fonksiyonu çağıramaz → **42501 permission denied**. Çözüm: `GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated; REVOKE EXECUTE ON FUNCTION public.is_admin() FROM anon;`.

#### 4.1.2 `profiles_update_own` Policy — Admin Yetkisi
Admin panelden rol değiştirme (`admin_dashboard_screen.dart`) şu akışı izler: `profiles UPDATE` → `profiles_update_own` policy → `is_admin()` çağrısı → yetki kontrolü. Bu akışın çalışması için:
1. `is_admin()` fonksiyonuna `authenticated` EXECUTE yetkisi olmalı.
2. Policy'de `is_admin()` çağrısı olmalı (veya `auth_is_admin()` çağrılıyorsa o fonksiyonun yetkileri tam olmalı).

Mevcut durum (DIAG 2026-07-02 teyitli): `profiles_update_own` → `is_admin()` çağırıyor. `is_admin()` → authenticated EXECUTE **yoktu**, `FIX_IS_ADMIN_PERMISSION_42501.sql` ile eklendi.

#### 4.1.3 orders_policy'de `is_admin()` Kullanımı — Alternatif Yaklaşım
orders policy'lerde admin kontrolü için `is_admin()` helper fonksiyonu KULLANILMAMALIDIR (V3_2 öğrenme). Bunun yerine doğrudan `EXISTS(SELECT 1 FROM profiles WHERE id=(SELECT auth.uid()) AND role='admin')` subquery kullanılmalı. Çünkü helper fonksiyon → SECURITY DEFINER → `auth.uid()` → `is_admin()` zinciri → RLS recursion veya yetki hatası riski taşır.

#### 4.1.4 Courier Assignments — orders_policy Recursion Riski
`courier_assignments` tablosunun policy'si `orders` tablosunu sorguluyorsa ve orders policy'si `courier_assignments`'i sorguluyorsa sonsuz döngü (42P17) oluşur. Çözüm: orders policy'de doğrudan tablo sorgusu yerine `assigned_courier_id` denormalize kolonu kullanılır (V3_2 yaklaşımı).

#### 4.1.5 `group_members` — Rol Yükseltme Açığı (2026-07-04, KRİTİK)
`group_members` tablosu üzerinde birbirini geçersiz kılan çok sayıda geçmiş migration vardı (GROUP_CHAT_SETUP → GROUP_CHAT_LINTER_FIX → FIX_GROUP_MEMBERS_INFINITE_RECURSION → FIX_OPEN_GROUP_JOIN → FIX_GROUP_MEMBERS_RLS_FINAL → FIX_GROUP_RLS_CLEAN_POLICIES → **FIX_GROUP_MEMBERS_RLS_BYPASS** — bu son dosya RLS'yi tamamen `DISABLE` ediyordu). Bulunan iki gerçek açık:

1. **Rol kendi kendine yükseltme**: "kendi satırını güncelleyebilir" UPDATE politikası `role` kolonunu da kapsıyordu — normal bir üye `.update({'role':'admin'})` ile kendini admin yapabiliyordu. RLS `USING`/`WITH CHECK` kolon bazlı fark göremediği için bu **BEFORE UPDATE trigger** (`trg_prevent_group_member_role_self_escalation`) ile kapatıldı — admin olmayan biri `role`'ü değiştiremiyor artık.
2. **Private gruba doğrudan INSERT ile katılım**: bazı geçmiş politika sürümlerinde INSERT için tek şart `user_id = auth.uid()` idi, `is_private` kontrolü yoktu → join-request onay akışı tamamen atlanabiliyordu.

Kanonik/güncel durum: `20260704_GROUP_SYSTEM_SECURITY_FIX_FINAL.sql` — bu dosya idempotenttir, tekrar çalıştırılabilir, hangi eski migration sırayla uygulanmış olursa olsun tutarlı son durumu garanti eder. **Bu tabloda yeni bir politika değişikliği yapılacaksa önce bu dosya referans alınmalı**, eski dosyalardan biri tekrar çalıştırılmamalı.

Ayrıca RLS/trigger içi yardımcı fonksiyonlar (`is_group_admin`, `is_group_member`, trigger fonksiyonu) ve `admin_add_group_member` RPC'si `anon` rolüne gereksiz şekilde açıktı (linter uyarısı) — `20260704_GROUP_LINTER_SECURITY_FIX.sql` ile EXECUTE yetkisi kısıtlandı.

### 4.2 Standart Audit Checklist

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