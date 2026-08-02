# CizreApp - Kapsamlı Hata Analizi ve Çözüm Planı

**Tarih:** 2026-07-28
**Proje Ref:** `xsbukxkgtmdyickknqzf`
**Analiz Edilen Modül Sayısı:** 23 servis + 14 modül
**Toplam Hata:** 47 (5 Kritik, 7 Orta, 35+ Düşük/İyileştirme)

---

## 📋 İçindekiler (Modüller Sırasıyla)

1. [Auth (Giriş/Kayıt)](#1-auth-modülü)
2. [Chat (Mesajlaşma)](#2-chat-modülü)
3. [Market (E-ticaret)](#3-market-modülü)
4. [Order (Sipariş)](#4-order-modülü)
5. [Payment & Wallet (Ödeme/Cüzdan)](#5-payment--wallet-modülü)
6. [Storage (Depolama)](#6-storage-modülü)
7. [Social (Sosyal Medya)](#7-social-modülü)
8. [Admin Panel](#8-admin-panel)
9. [Core/Theme](#9-coretheme)
10. [Main/Initialization](#10-maininitialization)
11. [Notification Service](#11-notification-service)
12. [SMM (Dijital Ürün)](#12-smm-dijital-ürün)
13. [Courier (Kurye)](#13-courier-kurye)
14. [News (Haberler)](#14-news-haberler)

---

## 🚨 Hata Öncelik Tablosu (Hızlı Referans)

| # | Modül | Satır | Hata | Seviye | Durum |
|---|-------|-------|------|--------|-------|
| 1 | Chat | 682 | Realtime filtre mantık hatası | 🚨 Kritik | ⏳ |
| 2 | Order | 142-197 | Order_items kaydedilmiyor (RLS) | 🚨 Kritik | ⏳ |
| 3 | Storage | 349-350 | fileExists yanlış implementasyon | 🚨 Kritik | ⏳ |
| 4 | Product | 89 | SQL injection potansiyeli | 🚨 Kritik | ⏳ |
| 5 | Order | 64, 762 | Order number çakışma | 🚨 Kritik | ⏳ |
| 6 | Theme | 25-27 | Constructor'da async await yok | ⚠️ Orta | ⏳ |
| 7 | Cart | 127-132 | Varyantsız duplicate item | ⚠️ Orta | ⏳ |
| 8 | Logger | 62-67 | Production crash tracking yok | ⚠️ Orta | ⏳ |
| 9 | Order | 220-249 | Email UI block | ⚠️ Orta | ⏳ |
| 10 | Error Handler | 181 | Bozuk UTF-8 karakter | ⚠️ Orta | ⏳ |
| 11 | Main | 432-483 | Dead code _showEmailConfirmedDialog | ⚠️ Orta | ⏳ |
| 12 | Main | 367, 413 | signedIn event çift işleniyor | ⚠️ Orta | ⏳ |
| 13 | Verification | 20 | Static rate limit multi-user | 📋 Düşük | ⏳ |
| 14 | Login | 26 | _authService dispose yok | 📋 Düşük | ⏳ |

---

# 1. AUTH MODÜLÜ

## 1.1 Analiz Edilen Dosyalar
- `lib/features/auth/services/auth_service.dart`
- `lib/features/auth/screens/login_screen.dart` (1003 satır)
- `lib/features/auth/screens/login_screen_v2.dart` (501 satır)
- `lib/features/auth/screens/register_screen.dart` (1569 satır)
- `lib/features/auth/screens/register_screen_v2.dart` (1471 satır)
- `lib/features/auth/screens/reset_password_screen.dart` (812 satır)
- `lib/features/auth/screens/reset_password_confirm_screen.dart` (296 satır)

## 1.2 Tespit Edilen Hatalar

### HATA-A1: LoginScreenV1 - Dead Code (V1 + V2 birlikte)
- **Dosya:** `lib/features/auth/screens/login_screen_v2.dart:768` (main.dart routes)
- **Sorun:** V1 eski sürüm, V2 yeni. İkisi de route'larda. Kod tekrarı ~1500 satır.
- **Etki:** Bakım maliyeti, V1'deki bug'lar kullanıcıya açık.
- **Çözüm:** V1'i silmeden önce production'dan log topla, sonra kaldır.

### HATA-A2: _authService Memory Leak
- **Dosya:** `lib/features/auth/screens/login_screen_v2.dart:26`
- **Kod:**
```dart
final _authService = AuthService();  // ⚠️ dispose() çağrılmıyor
```
- **Çözüm:** Static singleton yap.

### HATA-A3: Username Karşılaştırma Case-Sensitive
- **Dosya:** `lib/features/auth/screens/login_screen_v2.dart:57`
- **Kod:**
```dart
.eq('username', input.toLowerCase())  // ⚠️ DB'de username küçük harf mi?
```
- **Çözüm:** RLS'de ve DB'de `LOWER(username)` index'i ile unique constraint ekle.

### HATA-A4: Hata Mesajı Sızıntısı
- **Dosya:** `lib/features/auth/screens/login_screen_v2.dart:93`
- **Kod:**
```dart
} catch (e) {
  _showError(_authService.translateAuthError(e.toString()));  // ⚠️ Ham hata
}
```
- **Çözüm:** `FriendlyException.from(e)` kullan.

## 1.3 Supabase SQL Düzeltmeleri

```sql
-- =====================================================
-- DOSYA: supabase/migrations/20260728000001_auth_fixes.sql
-- AMAÇ: Auth username case-insensitive + error tracking
-- =====================================================

-- 1. Username unique constraint case-insensitive yap
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_username_unique;
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_username_lower 
  ON profiles (LOWER(username)) 
  WHERE username IS NOT NULL;

-- 2. Username arama fonksiyonu (case-insensitive)
CREATE OR REPLACE FUNCTION get_email_by_username(p_username TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT;
BEGIN
  SELECT email INTO v_email
  FROM profiles
  WHERE LOWER(username) = LOWER(p_username)
  LIMIT 1;
  
  RETURN v_email;
END;
$$;

REVOKE ALL FROM PUBLIC, anon;
GRANT EXECUTE TO authenticated;

-- 3. Login denemesi log tablosu (güvenlik için)
CREATE TABLE IF NOT EXISTS login_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email_or_username TEXT NOT NULL,
  ip_address INET,
  user_agent TEXT,
  success BOOLEAN DEFAULT FALSE,
  failure_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_login_attempts_email ON login_attempts (LOWER(email_or_username), created_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_attempts_created ON login_attempts (created_at DESC);

-- RLS: sadece service_role görebilir
ALTER TABLE login_attempts ENABLE ROW LEVEL SECURITY;
-- authenticated kullanıcı sadece kendi denemelerini görebilir
CREATE POLICY "Users can view own login attempts" ON login_attempts
  FOR SELECT TO authenticated
  USING (LOWER(email_or_username) = LOWER((SELECT email FROM auth.users WHERE id = auth.uid())));
```

## 1.4 Dart Düzeltmeleri

```dart
// lib/features/auth/screens/login_screen_v2.dart düzeltme

// ÖNCE:
final _authService = AuthService();

// SONRA:
static const _authService = AuthService();

// ÖNCE (satır 91-94):
} catch (e) {
  if (mounted) {
    _showError(_authService.translateAuthError(e.toString()));
  }
}

// SONRA:
} catch (e) {
  if (mounted) {
    _showError(FriendlyException.from(e).message);
  }
}
```

---

# 2. CHAT MODÜLÜ

## 2.1 Analiz Edilen Dosyalar
- `lib/features/chat/services/chat_service.dart` (864 satır)
- `lib/features/chat/services/group_chat_service.dart` (1390 satır)
- `lib/features/chat/services/presence_service.dart`

## 2.2 Tespit Edilen Hatalar

### HATA-C1: Realtime Filtre Mantık Hatası ⭐ EN KRİTİK
- **Dosya:** `lib/features/chat/services/chat_service.dart:682`
- **Kod:**
```dart
// ❌ YANLIŞ
if (msg.conversationId == conversationId || msg.senderId != currentUserId) {
  onEvent(InsertMessageEvent(msg));
}
```
- **Etki:** Mailbox modelinde, karşı tarafın mesajı partner conv'undan geldiğinde bu ekranda da görünür. **Çift mesaj gösterme bug'ı.**
- **Örnek:** A kullanıcısı B'ye mesaj gönderir. A'nın ekranında mesaj 1 kez görünmeli, ama mailbox modelinde A'nın conv'unda + B'nin conv'unda satır var. A kendi ekranındayken realtime UPDATE/INSERT geldiğinde **iki kez** tetiklenir.
- **Çözüm:** `&&` kullan.

### HATA-C2: Channel Duplicate Remove Etkisiz
- **Dosya:** `lib/features/chat/services/chat_service.dart:752-753`
- **Kod:**
```dart
final existingChannel = _supabase.channel(channelName);
_supabase.removeChannel(existingChannel);
```
- **Etki:** `_supabase.channel(name)` sadece handle oluşturur, gerçek subscription başlatmaz. `removeChannel` boş handle üzerinde çalışır → duplicate önlenmez.
- **Çözüm:** Subscribe olmuş kanalları takip et veya benzersiz channel adı kullan.

### HATA-C3: Mailbox Modelinde Mesaj Çift Görüntüleme
- **Dosya:** `lib/features/chat/services/chat_service.dart:395-433` (getMessages)
- **Sorun:** `getMessages` zaten deduplication yapıyor ama realtime INSERT'te yapılmıyor. Tutarsız.
- **Çözüm:** Realtime INSERT'te de aynı tekilleştirme mantığını uygula.

### HATA-C4: markMessagesAsRead Yanlış Conversation
- **Dosya:** `lib/features/chat/services/chat_service.dart:601`
- **Kod:**
```dart
if (convUserId != currentUserId) return; // Sadece conversation sahibi işaretlesin
```
- **Sorun:** Mailbox modelinde her kullanıcı kendi conv'unda okundu işaretler. Doğru ama UI'dan `conversationId` parametresi olarak hangisi geçiliyor?
- **Çözüm:** UI tarafında conversation_id olarak `currentUserId`-user olan conv seçilmeli.

### HATA-C5: Group Chat Service'de NotificationService Eager Init
- **Dosya:** `lib/features/chat/services/group_chat_service.dart:18`
- **Kod:**
```dart
final _notificationService = NotificationService();
```
- **Sorun:** Field initializer lazy değil, her instance oluşturulduğunda service başlatılır.
- **Çözüm:** `static const _notificationService = NotificationService();`

## 2.3 Supabase SQL Düzeltmeleri

```sql
-- =====================================================
-- DOSYA: supabase/migrations/20260728000002_chat_rls_fixes.sql
-- AMAÇ: Chat RLS + realtime filter düzeltmeleri
-- =====================================================

-- 1. Conversations mailbox RLS kontrolü
DROP POLICY IF EXISTS "Users can view own conversations" ON conversations;
CREATE POLICY "Users can view own conversations" ON conversations
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR other_user_id = auth.uid());

-- 2. Messages RLS - sadece kendi conv'undaki mesajları görebilir
DROP POLICY IF EXISTS "Users can view messages in own conversations" ON messages;
CREATE POLICY "Users can view messages in own conversations" ON messages
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND (c.user_id = auth.uid() OR c.other_user_id = auth.uid())
    )
  );

-- 3. Message INSERT - sadece kendi conv'una
DROP POLICY IF EXISTS "Users can insert messages to own conversations" ON messages;
CREATE POLICY "Users can insert messages to own conversations" ON messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND (c.user_id = auth.uid() OR c.other_user_id = auth.uid())
    )
  );

-- 4. mark_messages_as_read fonksiyonu - mailbox uyumlu
CREATE OR REPLACE FUNCTION mark_messages_as_read(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user UUID := auth.uid();
  v_other_user UUID;
  v_conv_owner UUID;
BEGIN
  IF v_current_user IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Conversation bilgilerini al
  SELECT user_id, other_user_id INTO v_conv_owner, v_other_user
  FROM conversations
  WHERE id = p_conversation_id;

  -- Sadece conversation sahibi okundu işaretleyebilir
  IF v_conv_owner != v_current_user THEN
    RETURN;
  END IF;

  -- Karşı tarafın mesajlarını okundu yap
  UPDATE messages
  SET is_read = TRUE, updated_at = NOW()
  WHERE conversation_id = p_conversation_id
    AND sender_id = v_other_user
    AND is_read = FALSE;

  -- Conversation unread_count sıfırla
  UPDATE conversations
  SET unread_count = 0, updated_at = NOW()
  WHERE id = p_conversation_id
    AND user_id = v_current_user;

  -- PARTNER conv'una DOKUNMA (eski bug buydu)
END;
$$;

REVOKE ALL FROM PUBLIC, anon;
GRANT EXECUTE TO authenticated, service_role;

-- 5. Realtime publication'da filter (performance)
-- Supabase realtime'da tüm mesajlar gönderilir, client filtreler.
-- Production'da server-side filter eklemek için:
ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS messages;
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
```

## 2.4 Dart Düzeltmeleri

```dart
// lib/features/chat/services/chat_service.dart satır 682 düzeltme

// ÖNCE:
if (msg.conversationId == conversationId || msg.senderId != currentUserId) {
  onEvent(InsertMessageEvent(msg));
}

// SONRA:
if (msg.conversationId == conversationId && msg.senderId != currentUserId) {
  onEvent(InsertMessageEvent(msg));
}
```

```dart
// lib/features/chat/services/group_chat_service.dart satır 18 düzeltme

// ÖNCE:
final _notificationService = NotificationService();

// SONRA:
static const _notificationService = NotificationService();
```

---

# 3. MARKET MODÜLÜ

## 3.1 Analiz Edilen Dosyalar
- `lib/features/market/services/product_service.dart` (428 satır)
- `lib/features/market/services/cart_service.dart` (513 satır)
- `lib/features/market/services/shop_service.dart` (347 satır)
- `lib/features/market/services/category_service.dart` (165 satır)
- `lib/features/market/services/product_review_service.dart` (444 satır)
- `lib/features/market/services/flash_sale_service.dart` (200 satır)
- `lib/features/market/services/daily_deal_service.dart` (120 satır)

## 3.2 Tespit Edilen Hatalar

### HATA-M1: SQL Injection Potansiyeli ⭐ KRİTİK
- **Dosya:** `lib/features/market/services/product_service.dart:89`
- **Kod:**
```dart
.or('name.ilike.%$query%,description.ilike.%$query%')  // ⚠️
```
- **Etki:** `query` içinde `,` veya `%` varsa Postgrest parse hatası → runtime exception.
- **Çözüm:** `.ilike()` ve escape fonksiyonu.

### HATA-M2: getPopularProducts Yanlış İsim
- **Dosya:** `lib/features/market/services/product_service.dart:137-152`
- **Kod:**
```dart
// "En popüler ürünleri getir (satış sayısına göre)" diyor ama:
.order('created_at', ascending: false)  // Sadece tarihe göre sıralıyor
```
- **Çözüm:** `posts.likes_count` veya `sales_count` kolonuna göre sırala.

### HATA-M3: addProduct 28 Parametre
- **Dosya:** `lib/features/market/services/product_service.dart:239-295`
- **Etki:** Bakımı zor, gelecekteki alanlar eklenince daha da büyür.
- **Çözüm:** `ProductInput` DTO class'ı oluştur.

### HATA-M4: Cart Varyantsız Duplicate
- **Dosya:** `lib/features/market/services/cart_service.dart:127-132`
- **Kod:**
```dart
if (response.isNotEmpty) {
  existingItem = _mapToCartItem(response.first);  // ⚠️ İLK eşleşen
}
```
- **Etki:** Aynı varyantsız üründen 3 ayrı cart satırı varsa, sadece 1'i alınır. Miktar artışı yanlış.

### HATA-M5: getCartSummary N+1 Query
- **Dosya:** `lib/features/market/services/cart_service.dart:278-287`
- **Kod:**
```dart
for (final entry in grouped.entries) {
  final info = await getShopDeliveryInfo(entry.key);  // ⚠️ Her dükkan için ayrı sorgu
}
```
- **Etki:** 5 dükkanlı sepette 5 ayrı SELECT.
- **Çözüm:** `.inFilter()` ile tek sorgu.

### HATA-M6: Generic throw Exception (59 dosyada)
- **Sorun:** Çoğu market servisi `throw Exception('X hatası: $e')` kullanıyor.
- **Çözüm:** Tüm servislere `FriendlyException.from(e)`.

## 3.3 Supabase SQL Düzeltmeleri

```sql
-- =====================================================
-- DOSYA: supabase/migrations/20260728000003_market_fixes.sql
-- AMAÇ: Cart unique constraint + product search index
-- =====================================================

-- 1. Cart tablosuna unique constraint ekle (aynı ürün + aynı varyanttan 1 satır)
-- Önce duplicate'leri temizle
DELETE FROM cart a USING cart b
WHERE a.id < b.id
  AND a.user_id = b.user_id
  AND a.product_id = b.product_id
  AND COALESCE(a.variant_data::text, '') = COALESCE(b.variant_data::text, '');

ALTER TABLE cart ADD CONSTRAINT cart_user_product_variant_unique
  UNIQUE (user_id, product_id, variant_data);

-- 2. Product search için GIN index (full-text search)
CREATE INDEX IF NOT EXISTS idx_products_name_search 
  ON products USING gin (to_tsvector('simple', name));
CREATE INDEX IF NOT EXISTS idx_products_desc_search 
  ON products USING gin (to_tsvector('simple', description));

-- 3. Composite index - mağaza + kategori + fiyat filtreleri
CREATE INDEX IF NOT EXISTS idx_products_shop_available_created 
  ON products (shop_id, is_available, created_at DESC)
  WHERE is_available = TRUE;

CREATE INDEX IF NOT EXISTS idx_products_category_price 
  ON products (category, price)
  WHERE is_available = TRUE;

-- 4. products tablosuna sales_count kolonu (popularity için)
ALTER TABLE products ADD COLUMN IF NOT EXISTS sales_count INTEGER DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_products_sales_count 
  ON products (sales_count DESC) WHERE is_available = TRUE;

-- 5. Sipariş tamamlandığında sales_count artıran trigger
CREATE OR REPLACE FUNCTION increase_product_sales_count()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
    UPDATE products p
    SET sales_count = p.sales_count + oi.quantity
    FROM order_items oi
    WHERE oi.order_id = NEW.id
      AND oi.product_id = p.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_increase_sales_count ON orders;
CREATE TRIGGER trg_increase_sales_count
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  EXECUTE FUNCTION increase_product_sales_count();

-- 6. Shop delivery info toplu getirme (N+1 çözümü)
CREATE OR REPLACE FUNCTION get_shops_delivery_info(p_shop_ids UUID[])
RETURNS TABLE (
  shop_id UUID,
  delivery_fee NUMERIC,
  free_delivery_min_amount NUMERIC,
  name TEXT
)
LANGUAGE sql
STABLE
AS $$
  SELECT id, delivery_fee, free_delivery_min_amount, name
  FROM shops
  WHERE id = ANY(p_shop_ids);
$$;

REVOKE ALL FROM PUBLIC, anon;
GRANT EXECUTE TO authenticated;

-- 7. RLS fix - products zaten selectable ama admin update
DROP POLICY IF EXISTS "Anyone can view available products" ON products;
CREATE POLICY "Anyone can view available products" ON products
  FOR SELECT TO anon, authenticated
  USING (is_available = TRUE);

-- 8. Cart RLS kontrolü
DROP POLICY IF EXISTS "Users manage own cart" ON cart;
CREATE POLICY "Users manage own cart" ON cart
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
```

## 3.4 Dart Düzeltmeleri

```dart
// lib/features/market/services/product_service.dart satır 89 düzeltme

// ÖNCE:
Future<List<Product>> searchProducts(String query) async {
  final response = await supabase
      .from('products')
      .select()
      .eq('is_available', true)
      .or('name.ilike.%$query%,description.ilike.%$query%')
      .order('created_at', ascending: false)
      .limit(50);
  ...
}

// SONRA:
String escapeLike(String s) => s.replaceAll('%', r'\%').replaceAll('_', r'\_');

Future<List<Product>> searchProducts(String query) async {
  final escaped = escapeLike(query);
  final response = await supabase
      .from('products')
      .select()
      .eq('is_available', true)
      .or('name.ilike.%${escaped}%,description.ilike.%${escaped}%')
      .order('created_at', ascending: false)
      .limit(50);
  ...
}
```

```dart
// lib/features/market/services/cart_service.dart - getCartSummary düzeltme

// ÖNCE (satır 272-287):
final grouped = <String, List<CartItem>>{};
for (final item in items) {
  final sid = item.shopId;
  if (sid == null) continue;
  grouped.putIfAbsent(sid, () => []).add(item);
}
for (final entry in grouped.entries) {
  final info = await getShopDeliveryInfo(entry.key);  // ⚠️ N+1
  ...
}

// SONRA (toplu RPC):
if (deliveryFee == null && grouped.isNotEmpty) {
  final shopIds = grouped.keys.toList();
  final response = await _supabase.rpc('get_shops_delivery_info', params: {
    'p_shop_ids': shopIds,
  });
  final shopInfoMap = <String, Map<String, dynamic>>{};
  for (final row in (response as List)) {
    shopInfoMap[row['shop_id'] as String] = Map<String, dynamic>.from(row);
  }
  for (final entry in grouped.entries) {
    final info = shopInfoMap[entry.key];
    if (info == null) continue;
    final shopTotal = entry.value.fold<double>(0, (s, it) => s + it.itemTotal);
    fee += calculateDeliveryFee(
      shopTotal,
      (info['delivery_fee'] as num?)?.toDouble() ?? 15.0,
      (info['free_delivery_min_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
```

---

# 4. ORDER MODÜLÜ

## 4.1 Analiz Edilen Dosyalar
- `lib/features/shop/services/order_service.dart` (955 satır)
- `lib/core/services/order_availability_service.dart`

## 4.2 Tespit Edilen Hatalar

### HATA-O1: Order Items Veri Kaybı ⭐ EN KRİTİK
- **Dosya:** `lib/features/shop/services/order_service.dart:142-197`
- **Kod:**
```dart
} catch (selectError) {
  // SELECT policy'sine takildi ama veri database'de var
  order = Order(
    id: 'ORDER_${DateTime.now().millisecondsSinceEpoch}',  // ⚠️ UUID değil
    ...
  );
  selectSuccess = false;
}

if (selectSuccess) {  // ⚠️ false ise items eklenmez
  for (var item in items) {
    await _supabase.from('order_items').insert({...});
  }
}
```
- **Etki:** RLS recursive hatası durumunda **sipariş var ama öğeleri kayıp**.

### HATA-O2: Order Number Çakışma
- **Dosya:** `lib/features/shop/services/order_service.dart:64, 762`
- **Kod:**
```dart
final orderNumber = 'ORD${DateTime.now().millisecondsSinceEpoch}';
```
- **Etki:** Aynı ms'de 2 sipariş → unique constraint → sipariş kaybolur.

### HATA-O3: Email UI Block
- **Dosya:** `lib/features/shop/services/order_service.dart:220-249`
- **Kod:**
```dart
_emailService.sendNewOrderEmailToSeller(...);  // ⚠️ fire-and-forget değil
```
- **Etki:** Email gönderimi ana thread'de await edilmeden network call.

### HATA-O4: Order Items Tek-tek INSERT
- **Dosya:** `lib/features/shop/services/order_service.dart:174-186`
- **Etki:** 10 öğeli siparişte 10 ayrı INSERT → yavaş.

### HATA-O5: updateOrderStatus 2x DB Read
- **Dosya:** `lib/features/shop/services/order_service.dart:425-453`
- **Sorun:** Önce `getOrderById` çağrılıyor, sonra UPDATE. Tek sorguda yapılabilir.

### HATA-O6: Fatura Bilgileri Tekrarlı
- **Dosya:** `lib/features/shop/services/order_service.dart:96-102, 788-794`
- **Etki:** Aynı 7 satır `if (invoiceData['x'] != null) 'x': invoiceData['x']` 2 yerde tekrarlanıyor.

## 4.3 Supabase SQL Düzeltmeleri

```sql
-- =====================================================
-- DOSYA: supabase/migrations/20260728000004_order_fixes.sql
-- AMAÇ: Order items veri kaybı fix + order number unique
-- =====================================================

-- 1. orders tablosunda RLS recursive kontrol
-- Mevcut policy'leri kontrol et
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'orders';

-- 2. Orders RLS - sadece participant'lar görebilir
DROP POLICY IF EXISTS "Users can view own orders" ON orders;
CREATE POLICY "Users can view own orders" ON orders
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Shop owners can view shop orders" ON orders;
CREATE POLICY "Shop owners can view shop orders" ON orders
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM shops s
      WHERE s.id = orders.shop_id
        AND s.owner_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Admins can view all orders" ON orders;
CREATE POLICY "Admins can view all orders" ON orders
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
  );

-- 3. Order items RLS - sipariş katılımcıları görebilir
DROP POLICY IF EXISTS "Users can view own order items" ON order_items;
CREATE POLICY "Users can view own order items" ON order_items
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_items.order_id
        AND (
          o.user_id = auth.uid() OR
          EXISTS (
            SELECT 1 FROM shops s
            WHERE s.id = o.shop_id AND s.owner_id = auth.uid()
          ) OR
          EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid() AND p.role = 'admin'
          )
        )
    )
  );

-- 4. order_number sequence (UUID yerine güvenli unique number)
CREATE SEQUENCE IF NOT EXISTS order_number_seq START 100000;

-- 5. orders insert trigger - otomatik order_number
CREATE OR REPLACE FUNCTION generate_order_number()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.order_number IS NULL OR NEW.order_number = '' THEN
    NEW.order_number := 'ORD' || LPAD(nextval('order_number_seq')::TEXT, 8, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_generate_order_number ON orders;
CREATE TRIGGER trg_generate_order_number
  BEFORE INSERT ON orders
  FOR EACH ROW
  EXECUTE FUNCTION generate_order_number();

-- 6. order_number unique constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'orders_order_number_unique'
  ) THEN
    ALTER TABLE orders ADD CONSTRAINT orders_order_number_unique UNIQUE (order_number);
  END IF;
END $$;

-- 7. Sipariş oluşturma RPC (transactional - order + items atomik)
CREATE OR REPLACE FUNCTION create_order_with_items(
  p_user_id UUID,
  p_shop_id UUID,
  p_items JSONB,
  p_delivery_address_text TEXT,
  p_address_id UUID,
  p_customer_phone TEXT,
  p_payment_method TEXT,
  p_subtotal NUMERIC,
  p_delivery_fee NUMERIC,
  p_discount NUMERIC,
  p_total NUMERIC,
  p_notes TEXT,
  p_invoice_data JSONB DEFAULT '{}'::JSONB
)
RETURNS TABLE (
  order_id UUID,
  order_number TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id UUID;
  v_order_number TEXT;
  v_item JSONB;
BEGIN
  -- Siparişi oluştur
  INSERT INTO orders (
    user_id, shop_id, delivery_address_text, address_id,
    customer_phone, payment_method, payment_status,
    subtotal, delivery_fee, discount, total,
    status, notes,
    invoice_type, invoice_full_name, invoice_tax_number, invoice_tc_no,
    invoice_tax_office, invoice_address, invoice_email
  ) VALUES (
    p_user_id, p_shop_id, p_delivery_address_text, p_address_id,
    p_customer_phone, p_payment_method, 'pending',
    p_subtotal, p_delivery_fee, p_discount, p_total,
    'pending', p_notes,
    p_invoice_data->>'invoice_type',
    p_invoice_data->>'invoice_full_name',
    p_invoice_data->>'invoice_tax_number',
    p_invoice_data->>'invoice_tc_no',
    p_invoice_data->>'invoice_tax_office',
    p_invoice_data->>'invoice_address',
    p_invoice_data->>'invoice_email'
  )
  RETURNING id, order_number INTO v_order_id, v_order_number;

  -- Items ekle
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO order_items (
      order_id, product_id, product_name, price, product_price,
      quantity, subtotal, product_image_url, shop_id, shop_name
    ) VALUES (
      v_order_id,
      (v_item->>'product_id')::UUID,
      v_item->>'product_name',
      (v_item->>'price')::NUMERIC,
      (v_item->>'price')::NUMERIC,
      (v_item->>'quantity')::INTEGER,
      (v_item->>'subtotal')::NUMERIC,
      v_item->>'product_image_url',
      (v_item->>'shop_id')::UUID,
      v_item->>'shop_name'
    );
  END LOOP;

  RETURN QUERY SELECT v_order_id, v_order_number;
END;
$$;

REVOKE ALL FROM PUBLIC, anon;
GRANT EXECUTE TO authenticated, service_role;
```

## 4.4 Dart Düzeltmeleri

```dart
// lib/features/shop/services/order_service.dart - createOrder düzeltme

// ÖNCE (satır 73-167):
try {
  await _supabase.from('orders').insert({...});
  // ... SELECT ...
} catch (selectError) {
  order = Order(id: 'ORDER_${DateTime.now().millisecondsSinceEpoch}', ...);
  selectSuccess = false;
}
if (selectSuccess) {
  for (var item in items) {
    await _supabase.from('order_items').insert({...});  // ⚠️ Veri kaybı riski
  }
}

// SONRA (RPC kullan):
final response = await _supabase.rpc('create_order_with_items', params: {
  'p_user_id': userId,
  'p_shop_id': shopId,
  'p_items': items.map((item) => {
    'product_id': item.productId,
    'product_name': item.productName,
    'price': item.price,
    'quantity': item.quantity,
    'subtotal': item.subtotal,
    'product_image_url': item.productImageUrl,
    'shop_id': item.shopId,
    'shop_name': item.shopName,
  }).toList(),
  'p_delivery_address_text': deliveryAddressText,
  'p_address_id': addressId,
  'p_customer_phone': customerPhone,
  'p_payment_method': paymentMethod.name,
  'p_subtotal': subtotal,
  'p_delivery_fee': deliveryFee,
  'p_discount': discount,
  'p_total': total,
  'p_notes': notes,
  'p_invoice_data': invoiceInfo?.toOrderSnapshot() ?? {},
});

final result = (response as List).first;
final orderId = result['order_id'] as String;
final orderNumber = result['order_number'] as String;

// Order'ı getir
final order = await getOrderById(orderId);

// Email gönder (fire-and-forget)
unawaited(_emailService.sendNewOrderEmailToSeller(...));
unawaited(_emailService.sendNewOrderEmailToAdmin(...));
```

```dart
// Order number çakışma düzeltme
// ÖNCE:
final orderNumber = 'ORD${DateTime.now().millisecondsSinceEpoch}';

// SONRA: Order_number SQL trigger tarafından otomatik oluşturulur
// Dart tarafında NULL gönder veya boş bırak
'order_number': null,  // SQL trigger otomatik atar
```

---

# 5. PAYMENT & WALLET MODÜLÜ

## 5.1 Analiz Edilen Dosyalar
- `lib/core/services/payment_service.dart` (238 satır)
- `lib/core/services/balance_service.dart`
- `lib/core/services/withdrawal_service.dart`
- `lib/core/services/transfer_service.dart`
- `lib/features/wallet/screens/wallet_screen.dart`
- `lib/features/wallet/screens/topup_screen.dart`
- `lib/features/wallet/screens/transaction_history_screen.dart`

## 5.2 Tespit Edilen Hatalar

### HATA-P1: Payment Warm-up Yanlış Return Type
- **Dosya:** `lib/core/services/payment_service.dart:185`
- **Kod:**
```dart
return FunctionResponse(status: 408, data: {});  // ⚠️ Tip uyumsuz olabilir
```
- **Çözüm:** Timeout'ta return etme, exception throw et.

### HATA-P2: isOrphanSuccess Dead Code
- **Dosya:** `lib/core/services/payment_service.dart:232`
- **Kod:**
```dart
bool get isOrphanSuccess => false;  // ⚠️ Her zaman false
```
- **Çözüm:** Sil.

### HATA-P3: Balance RPC Güvensiz Parametre
- **Dosya:** `lib/core/services/balance_service.dart:81-143`
- **Sorun:** `useBalanceForOrder` RPC'ye `order_total` gönderiyor ama RPC bunu kullanmıyor.
- **Etki:** Frontend müdahale edebilir.

### HATA-P4: Wallet Transaction History N+1
- **Dosya:** `lib/core/services/balance_service.dart` (transaction_history kısmı)
- **Etki:** Her transaction için profile fetch.

## 5.3 Supabase SQL Düzeltmeleri

```sql
-- =====================================================
-- DOSYA: supabase/migrations/20260728000005_payment_fixes.sql
-- AMAÇ: Payment + balance güvenlik + dead code temizliği
-- =====================================================

-- 1. payment_transactions tablosunda status enum kontrol
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_status_enum') THEN
    CREATE TYPE payment_status_enum AS ENUM ('pending', 'success', 'failure', 'cancelled', 'error');
  END IF;
END $$;

-- 2. order_id ekle (zaten var olabilir, kontrol et)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'payment_transactions' AND column_name = 'order_id'
  ) THEN
    ALTER TABLE payment_transactions ADD COLUMN order_id UUID REFERENCES orders(id);
  END IF;
END $$;

-- 3. payment_transactions + order_id unique (idempotency)
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_transactions_order_id 
  ON payment_transactions(order_id) WHERE order_id IS NOT NULL;

-- 4. Balance RPC güvenlik - service_role kontrolü
CREATE OR REPLACE FUNCTION use_balance_for_order(
  p_order_id UUID,
  p_amount NUMERIC,
  p_order_total NUMERIC
)
RETURNS TABLE (
  transaction_id UUID,
  amount_paid NUMERIC,
  remaining_amount NUMERIC,
  new_balance NUMERIC,
  is_fully_paid BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_current_balance NUMERIC;
  v_amount_paid NUMERIC;
  v_new_balance NUMERIC;
  v_remaining NUMERIC;
  v_txn_id UUID;
BEGIN
  -- Auth kontrol
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;

  -- Sipariş sahibi kontrol
  IF NOT EXISTS (SELECT 1 FROM orders WHERE id = p_order_id AND user_id = v_user_id) THEN
    RAISE EXCEPTION 'Order not found or not authorized' USING ERRCODE = '42501';
  END IF;

  -- Mevcut bakiye
  SELECT balance INTO v_current_balance
  FROM user_balances
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_current_balance IS NULL THEN
    v_current_balance := 0;
  END IF;

  -- Hesapla
  v_amount_paid := LEAST(p_amount, v_current_balance);
  v_remaining := p_order_total - v_amount_paid;
  v_new_balance := v_current_balance - v_amount_paid;

  -- Bakiye düş
  IF v_amount_paid > 0 THEN
    UPDATE user_balances
    SET balance = v_new_balance, updated_at = NOW()
    WHERE user_id = v_user_id;

    -- Transaction kaydı
    INSERT INTO balance_transactions (
      user_id, amount, fee, type, reference_type, reference_id, description
    ) VALUES (
      v_user_id, v_amount_paid, 0, 'order_payment', 'order', p_order_id,
      'Sipariş ödemesi: ' || p_order_id::TEXT
    )
    RETURNING id INTO v_txn_id;
  END IF;

  -- Order güncelle
  UPDATE orders
  SET payment_status = CASE WHEN v_remaining <= 0 THEN 'paid' ELSE 'partial' END,
      updated_at = NOW()
  WHERE id = p_order_id;

  RETURN QUERY SELECT 
    v_txn_id, v_amount_paid, v_remaining, v_new_balance, (v_remaining <= 0);
END;
$$;

REVOKE ALL FROM PUBLIC, anon;
GRANT EXECUTE TO authenticated, service_role;

-- 5. Withdrawal rate limit
CREATE TABLE IF NOT EXISTS withdrawal_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  amount NUMERIC NOT NULL,
  status TEXT NOT NULL,
  error_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_withdrawal_attempts_user_created 
  ON withdrawal_attempts(user_id, created_at DESC);

-- 6. Daily withdrawal limit
CREATE OR REPLACE FUNCTION check_withdrawal_limit(p_user_id UUID, p_amount NUMERIC)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  v_today_total NUMERIC;
  v_daily_limit NUMERIC := 50000; -- 50K TL
BEGIN
  SELECT COALESCE(SUM(amount), 0) INTO v_today_total
  FROM withdrawal_attempts
  WHERE user_id = p_user_id
    AND status = 'success'
    AND created_at >= CURRENT_DATE;

  RETURN (v_today_total + p_amount) <= v_daily_limit;
END;
$$;

REVOKE ALL FROM PUBLIC, anon;
GRANT EXECUTE TO authenticated, service_role;
```

## 5.4 Dart Düzeltmeleri

```dart
// lib/core/services/payment_service.dart düzeltme

// ÖNCE (satır 181-186):
await supabase.functions.invoke(
  'iyzico-payment-init',
  body: {'ping': true},
).timeout(
  const Duration(seconds: 10),
  onTimeout: () {
    return FunctionResponse(status: 408, data: {});  // ⚠️
  },
);

// SONRA:
try {
  await supabase.functions.invoke(
    'iyzico-payment-init',
    body: {'ping': true},
  ).timeout(const Duration(seconds: 10));
} on TimeoutException {
  debugPrint('⚠️ PAYMENT WARM-UP: Timeout (10s) - devam ediliyor');
} catch (e) {
  debugPrint('⚠️ PAYMENT WARM-UP: Hata - $e');
}

// ÖNCE (satır 232):
bool get isOrphanSuccess => false;  // ⚠️ Dead code

// SONRA: SİL
```

---

# 6. STORAGE MODÜLÜ

## 6.1 Analiz Edilen Dosyalar
- `lib/core/services/storage_service.dart` (418 satır)

## 6.2 Tespit Edilen Hatalar

### HATA-S1: fileExists Mantık Hatası ⭐ KRİTİK
- **Dosya:** `lib/core/services/storage_service.dart:349-350`
- **Kod:**
```dart
final response = await client.storage.from(bucket).list(path: path);
return response.any((item) => item.name == path.split('/').last);
```
- **Sorun:** `path: "folder/file.jpg"` → `list(path:)` klasör arar, "folder/file.jpg" yanlış.
- **Çözüm:** Klasör + dosya adı ayrımı.

### HATA-S2: _isWebSupported Her Çağrıda Hesaplanıyor
- **Dosya:** `lib/core/services/storage_service.dart:41`
- **Kod:**
```dart
bool get _isWebSupported => !kIsWeb;  // ⚠️ static olabilir
```
- **Çözüm:** `static const _isWebSupported = !kIsWeb;`

### HATA-S3: S3 initS3 Web Kontrolü
- **Dosya:** `lib/core/services/storage_service.dart:62-65`
- **Sorun:** `_isWebSupported` false ise return ama `disableS3()` çağrılmıyor.
- **Çözüm:** `disableS3()` ekle.

## 6.3 Supabase SQL Düzeltmeleri

```sql
-- =====================================================
-- DOSYA: supabase/migrations/20260728000006_storage_fixes.sql
-- AMAÇ: Storage bucket RLS tutarlılık + path helpers
-- =====================================================

-- 1. Tüm storage bucket'ların RLS politikası
-- (Mevcut policy'leri koru, sadece eksik olanları ekle)

-- 2. Dosya var mı kontrolü için helper
CREATE OR REPLACE FUNCTION check_storage_object(
  p_bucket TEXT,
  p_path TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_exists BOOLEAN;
BEGIN
  -- service_role ile storage.objects sorgula
  SELECT EXISTS (
    SELECT 1 FROM storage.objects
    WHERE bucket_id = p_bucket
      AND name = p_path
  ) INTO v_exists;
  
  RETURN v_exists;
END;
$$;

REVOKE ALL FROM PUBLIC, anon;
GRANT EXECUTE TO authenticated, service_role;

-- 3. S3 ayarları için merkezi config tablosu kontrol
-- (zaten api_settings tablosu var, ek bir şey gerekmiyor)
-- Eğer s3_enabled, s3_access_key vs. kolonları yoksa:
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'api_settings' AND column_name = 's3_enabled'
  ) THEN
    ALTER TABLE api_settings ADD COLUMN s3_enabled BOOLEAN DEFAULT FALSE;
    ALTER TABLE api_settings ADD COLUMN s3_access_key TEXT;
    ALTER TABLE api_settings ADD COLUMN s3_secret_key TEXT;
    ALTER TABLE api_settings ADD COLUMN s3_bucket TEXT;
    ALTER TABLE api_settings ADD COLUMN s3_endpoint TEXT;
    ALTER TABLE api_settings ADD COLUMN s3_region TEXT DEFAULT 'us-east-1';
    ALTER TABLE api_settings ADD COLUMN s3_public_url TEXT;
  END IF;
END $$;

-- 4. api_settings RLS - sadece admin görebilir/düzenleyebilir
DROP POLICY IF EXISTS "Admins manage api settings" ON api_settings;
CREATE POLICY "Admins manage api settings" ON api_settings
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );
```

## 6.4 Dart Düzeltmeleri

```dart
// lib/core/services/storage_service.dart düzeltme

// ÖNCE (satır 41):
bool get _isWebSupported => !kIsWeb;

// SONRA:
static const _isWebSupported = !kIsWeb;

// ÖNCE (satır 62-65):
Future<void> initS3({...}) async {
  if (!_isWebSupported) {
    debugPrint('⚠️ S3 web platformunda desteklenmez');
    return;  // ⚠️ disableS3() eksik
  }
}

// SONRA:
Future<void> initS3({...}) async {
  if (!_isWebSupported) {
    debugPrint('⚠️ S3 web platformunda desteklenmez');
    disableS3();
    return;
  }
}

// ÖNCE (satır 340-355 - fileExists):
Future<bool> fileExists({required String bucket, required String path}) async {
  try {
    if (_s3Enabled && _minioClient != null && _isWebSupported) {
      final s3Bucket = _s3Bucket ?? bucket;
      await _minioClient!.statObject(s3Bucket, path);
      return true;
    } else {
      final client = _supabase;
      if (client == null) return false;
      
      final response = await client.storage.from(bucket).list(path: path);
      return response.any((item) => item.name == path.split('/').last);  // ⚠️
    }
  } catch (e) {
    return false;
  }
}

// SONRA:
Future<bool> fileExists({required String bucket, required String path}) async {
  try {
    if (_s3Enabled && _minioClient != null && _isWebSupported) {
      final s3Bucket = _s3Bucket ?? bucket;
      await _minioClient!.statObject(s3Bucket, path);
      return true;
    } else {
      final client = _supabase;
      if (client == null) return false;
      
      // path'i klasör + dosya adı olarak ayır
      final parts = path.split('/');
      final fileName = parts.last;
      final folder = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '';
      
      final response = await client.storage.from(bucket).list(path: folder);
      return response.any((item) => item.name == fileName);
    }
  } catch (e) {
    return false;
  }
}
```

---

# 7. SOCIAL MODÜLÜ

## 7.1 Analiz Edilen Dosyalar
- `lib/features/social/services/post_service.dart` (605 satır)
- `lib/features/social/services/story_service.dart` (869 satır)
- `lib/features/social/services/post_report_service.dart` (212 satır)
- `lib/features/social/screens/social_screen.dart`

## 7.2 Tespit Edilen Hatalar

### HATA-SO1: Post Service Eager Init
- **Dosya:** `lib/features/social/services/post_service.dart:23-27`
- **Kod:**
```dart
final _notificationService = NotificationService();
final _mentionService = MentionService();
final _cacheService = CacheService();
final _performanceMonitoringService = PerformanceMonitoringService();
final _analyticsService = AnalyticsService();
```
- **Etki:** Her PostService instance'ında 5 service oluşturulur.

### HATA-SO2: Story Service Memory Management
- **Dosya:** `lib/features/social/services/story_service.dart`
- **Sorun:** Story upload'larında büyük dosya yükleme ana thread'de.

### HATA-SO3: Analytics Her Post'ta Track
- **Dosya:** `lib/features/social/services/post_service.dart:75-78`
- **Etki:** Her feed load'da analytics event → gereksiz network.

## 7.3 Supabase SQL Düzeltmeleri

```sql
-- =====================================================
-- DOSYA: supabase/migrations/20260728000007_social_fixes.sql
-- AMAÇ: Posts RLS + realtime performance
-- =====================================================

-- 1. Posts tablosuna soft delete + is_active zaten var
-- Sadece RLS kontrolü

DROP POLICY IF EXISTS "Users can view active posts" ON posts;
CREATE POLICY "Users can view active posts" ON posts
  FOR SELECT TO authenticated, anon
  USING (is_active = TRUE);

DROP POLICY IF EXISTS "Users can insert own posts" ON posts;
CREATE POLICY "Users can insert own posts" ON posts
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own posts" ON posts;
CREATE POLICY "Users can update own posts" ON posts
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins can manage all posts" ON posts;
CREATE POLICY "Admins can manage all posts" ON posts
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 2. Post views counter trigger
CREATE OR REPLACE FUNCTION increment_post_view(p_post_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE posts
  SET views_count = COALESCE(views_count, 0) + 1
  WHERE id = p_post_id;
END;
$$;

REVOKE ALL FROM PUBLIC, anon;
GRANT EXECUTE TO authenticated, anon;

-- 3. Post likes unique constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'post_likes_post_user_unique'
  ) THEN
    ALTER TABLE post_likes ADD CONSTRAINT post_likes_post_user_unique UNIQUE (post_id, user_id);
  END IF;
END $$;

-- 4. Post likes count trigger
CREATE OR REPLACE FUNCTION update_post_likes_count()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE posts SET likes_count = COALESCE(likes_count, 0) + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE posts SET likes_count = GREATEST(COALESCE(likes_count, 0) - 1, 0) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_post_likes_count ON post_likes;
CREATE TRIGGER trg_post_likes_count
  AFTER INSERT OR DELETE ON post_likes
  FOR EACH ROW
  EXECUTE FUNCTION update_post_likes_count();

-- 5. Story 24 saat expire (zaten var olabilir kontrol et)
-- stories tablosu zaten expire_at kolonuna sahip
CREATE INDEX IF NOT EXISTS idx_stories_expire_at 
  ON stories (expire_at) WHERE is_active = TRUE;

-- 6. Post comment_mentions tablosu (zaten var)
CREATE INDEX IF NOT EXISTS idx_comment_mentions_user 
  ON comment_mentions (mentioned_user_id);
```

## 7.4 Dart Düzeltmeleri

```dart
// lib/features/social/services/post_service.dart düzeltme

// ÖNCE (satır 23-27):
final _notificationService = NotificationService();
final _mentionService = MentionService();
final _cacheService = CacheService();
final _performanceMonitoringService = PerformanceMonitoringService();
final _analyticsService = AnalyticsService();

// SONRA:
static const _notificationService = NotificationService();
static const _mentionService = MentionService();
static const _cacheService = CacheService();
static const _performanceMonitoringService = PerformanceMonitoringService();
static const _analyticsService = AnalyticsService();
```

---

# 8. ADMIN PANEL

## 8.1 Analiz Edilen Dosyalar
- `lib/features/admin/screens/admin_dashboard_screen.dart` (193 satır, part'lara bölünmüş)
- `lib/features/admin/screens/admin_dashboard_parts/_part_*.dart` (30+ part dosyası)
- `lib/features/admin/services/`

## 8.2 Tespit Edilen Hatalar

### HATA-AD1: Admin Dashboard Part Yapısı
- **Durum:** Zaten refactor edilmiş (admin_dashboard_bolme_2026_07_27.md planı uygulanmış).
- **Kontrol:** 193 satıra düşmüş, part'lar doğru kullanılıyor.

### HATA-AD2: Admin RPC Güvenlik
- **Sorun:** Admin RPC'lerde yetki kontrolü service_role tarafında yapılmalı.
- **Çözüm:** `SECURITY DEFINER` + `auth.uid()` kontrolü.

## 8.3 Supabase SQL Düzeltmeleri

```sql
-- =====================================================
-- DOSYA: supabase/migrations/20260728000008_admin_fixes.sql
-- AMAÇ: Admin RPC'lerde güvenlik + audit log
-- =====================================================

-- 1. Admin audit log tablosu
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL REFERENCES auth.users(id),
  action TEXT NOT NULL,
  target_table TEXT,
  target_id TEXT,
  old_data JSONB,
  new_data JSONB,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_admin_created 
  ON admin_audit_log (admin_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_action 
  ON admin_audit_log (action, created_at DESC);

ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins can view audit log" ON admin_audit_log;
CREATE POLICY "Admins can view audit log" ON admin_audit_log
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 2. Admin yetki kontrol fonksiyonu
CREATE OR REPLACE FUNCTION is_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = p_user_id AND role = 'admin'
  );
$$;

REVOKE ALL FROM PUBLIC, anon;
GRANT EXECUTE TO authenticated, service_role;

-- 3. Admin log fonksiyonu
CREATE OR REPLACE FUNCTION log_admin_action(
  p_action TEXT,
  p_target_table TEXT DEFAULT NULL,
  p_target_id TEXT DEFAULT NULL,
  p_old_data JSONB DEFAULT NULL,
  p_new_data JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;

  INSERT INTO admin_audit_log (
    admin_id, action, target_table, target_id, old_data, new_data
  ) VALUES (
    auth.uid(), p_action, p_target_table, p_target_id, p_old_data, p_new_data
  );
END;
$$;

REVOKE ALL FROM PUBLIC, anon;
GRANT EXECUTE TO authenticated, service_role;
```

---

# 9. CORE/THEME

## 9.1 Tespit Edilen Hatalar

### HATA-T1: ThemeProvider Race Condition
- **Dosya:** `lib/core/providers/theme_provider.dart:25-27`
- **Kod:**
```dart
ThemeProvider() {
  _loadTheme();  // ⚠️ await yok
}
```
- **Etki:** İlk frame'de yanlış tema.

### HATA-T2: Deprecated API
- **Dosya:** `lib/core/providers/theme_provider.dart:53, 83`
- **Kod:**
```dart
prefs.setInt('theme_color', color.value)  // ⚠️ Color.value deprecated
```

## 9.2 Supabase SQL Düzeltmeleri

```sql
-- Bu modül için DB düzeltmesi yok (client-only)
```

## 9.3 Dart Düzeltmeleri

```dart
// lib/core/providers/theme_provider.dart düzeltme

// ÖNCE:
ThemeProvider() {
  _loadTheme();
}

// SONRA:
ThemeProvider() {
  // Fire and forget - _loadTheme notifyListeners çağırır
  _loadTheme();
}

// VEYA daha güvenli:
class ThemeProvider with ChangeNotifier {
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;
  
  ThemeProvider() {
    _loadTheme();
  }
  
  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeValue = prefs.getInt('theme_color') ?? 0xFFD91A73;
      _primaryColor = Color(themeValue);
      _autoThemeEnabled = prefs.getBool('auto_theme_enabled') ?? true;
      // ... load theme
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }
}

// MainScreen'de:
Widget build(BuildContext context) {
  final themeProvider = context.watch<ThemeProvider>();
  if (!themeProvider.isLoaded) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
  // ... normal build
}
```

---

# 10. MAIN/INITIALIZATION

## 10.1 Tespit Edilen Hatalar

### HATA-MA1: signedIn Event 2x İşleniyor
- **Dosya:** `lib/main.dart:367, 413`
- **Etki:** Mantıksal kod tekrarı.

### HATA-MA2: _showEmailConfirmedDialog Dead Code
- **Dosya:** `lib/main.dart:432-483`
- **Etki:** 51 satır dead code.

### HATA-MA3: Hardcoded Supabase URL/Key
- **Dosya:** `lib/core/constants/app_constants.dart:8-9`
- **Sorun:** Public anon key public olsa da, kodda açıkça durması code review'da yanlış alarm.

## 10.2 Dart Düzeltmeleri

```dart
// lib/main.dart düzeltme

// ÖNCE (satır 367-410 + 413-420):
if (event == AuthChangeEvent.signedIn && session != null) {
  // email confirmation check...
}

if (event == AuthChangeEvent.signedIn && session != null) {  // ⚠️ 2. kez
  try {
    PresenceService.instance.startGlobalPresence(uid);
  } catch (e) { ... }
}

// SONRA:
if (event == AuthChangeEvent.signedIn && session != null) {
  // Email confirmation check
  final emailConfirmedAtStr = session.user.emailConfirmedAt;
  if (emailConfirmedAtStr != null) {
    try {
      final confirmedAt = DateTime.parse(emailConfirmedAtStr);
      final isJustConfirmed = DateTime.now().difference(confirmedAt).inSeconds < 60;
      if (isJustConfirmed && !_isWebProfileRoute) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            _navigatorKey.currentState?.pushNamedAndRemoveUntil('/main', (route) => false);
          }
        });
        return;
      }
    } catch (e) { /* ignore */ }
  }
  
  // Warm-up
  VerificationService.warmUpEdgeFunctions();
  PaymentService.warmUpEdgeFunctions();
  
  // Presence
  try {
    PresenceService.instance.startGlobalPresence(session.user.id);
  } catch (e) {
    print('presence start error: $e');
  }
}

// _showEmailConfirmedDialog (satır 432-483) - SİL
```

---

# 11. NOTIFICATION SERVICE

## 11.1 Tespit Edilen Hatalar

### HATA-N1: Eager Init
- **Dosya:** `lib/core/services/notification_service.dart:7`
- **Kod:**
```dart
final _preferencesService = NotificationPreferencesService();
```

### HATA-N2: Dedup Mantığı Tutarsız
- **Dosya:** `lib/core/services/notification_service.dart:54-73`
- **Sorun:** Title bazlı dedup, ama title değişirse aynı notification duplicate sayılır.

## 11.2 Supabase SQL Düzeltmeleri

```sql
-- =====================================================
-- DOSYA: supabase/migrations/20260728000009_notification_fixes.sql
-- AMAÇ: Notification RLS + realtime performance
-- =====================================================

-- 1. notifications tablosu RLS
DROP POLICY IF EXISTS "Users can view own notifications" ON notifications;
CREATE POLICY "Users can view own notifications" ON notifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own notifications" ON notifications;
CREATE POLICY "Users can update own notifications" ON notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- 2. Notification unique constraint (aynı tip + entity bir kez)
CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_user_entity_type 
  ON notifications (user_id, entity_id, type)
  WHERE entity_id IS NOT NULL;

-- 3. Bildirim insert trigger (auto dedup)
CREATE OR REPLACE FUNCTION dedup_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Aynı kullanıcı + entity + type için eski unread notification sil
  IF NEW.entity_id IS NOT NULL THEN
    DELETE FROM notifications
    WHERE user_id = NEW.user_id
      AND entity_id = NEW.entity_id
      AND type = NEW.type
      AND id != NEW.id
      AND is_read = FALSE;
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dedup_notification ON notifications;
CREATE TRIGGER trg_dedup_notification
  BEFORE INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION dedup_notification();

-- 4. Eski notification temizleme (30 günden eski)
DELETE FROM notifications
WHERE created_at < NOW() - INTERVAL '30 days'
  AND is_read = TRUE;
```

## 11.3 Dart Düzeltmeleri

```dart
// lib/core/services/notification_service.dart

// ÖNCE (satır 7):
final _preferencesService = NotificationPreferencesService();

// SONRA:
static const _preferencesService = NotificationPreferencesService();
```

---

# 12. SMM (DİJİTAL ÜRÜN)

## 12.1 Analiz Edilen Dosyalar
- `lib/core/services/smm_service.dart`
- `lib/features/market/services/agora_service.dart`
- `lib/features/market/services/live_shopping_service.dart`

## 12.2 Tespit Edilen Hatalar

### HATA-SMM1: SMM Kod Tekrarı
- **Dosya:** `supabase/functions/smm-order-manual-status/index.ts` ve `smm-order-status-check/index.ts`
- **Sorun:** `refundCustomer`, `notifyAdmins`, `notifyCustomer`, `creditSellerIfNeeded` 2 dosyada kopyalanmış.
- **Çözüm:** Supabase `_shared/` modülü desteklemediği için comment var. Shared lib oluştur.

### HATA-SMM2: SMM API Key Sızıntı Riski
- **Dosya:** `supabase/functions/smm-order-create/index.ts`
- **Kontrol:** `api_key` client'a hiç sızmamalı (zaten önlem var).

## 12.3 Supabase SQL Düzeltmeleri

```sql
-- =====================================================
-- DOSYA: supabase/migrations/20260728000010_smm_fixes.sql
-- AMAÇ: SMM provider RLS + rate limit
-- =====================================================

-- 1. SMM provider API key encryption (zaten var)
-- Sadece service_role görebilir
DROP POLICY IF EXISTS "Sellers manage own providers" ON smm_providers;
CREATE POLICY "Sellers manage own providers" ON smm_providers
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM shops
      WHERE id = smm_providers.shop_id AND owner_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Admins manage all providers" ON smm_providers;
CREATE POLICY "Admins manage all providers" ON smm_providers
  FOR ALL TO authenticated
  USING (is_admin());

-- 2. Digital orders RLS
DROP POLICY IF EXISTS "Users view own digital orders" ON digital_orders;
CREATE POLICY "Users view own digital orders" ON digital_orders
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Sellers view shop digital orders" ON digital_orders;
CREATE POLICY "Sellers view shop digital orders" ON digital_orders
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM shops s
      WHERE s.id = digital_orders.shop_id AND s.owner_id = auth.uid()
    )
  );

-- 3. SMM rate limit tablosu
CREATE TABLE IF NOT EXISTS smm_rate_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id UUID NOT NULL REFERENCES smm_providers(id),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  request_count INTEGER DEFAULT 1,
  window_start TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_smm_rate_limits_provider_user 
  ON smm_rate_limits (provider_id, user_id, created_at DESC);
```

---

# 13. COURIER (KURYE)

## 13.1 Analiz Edilen Dosyalar
- `lib/core/services/courier_request_service.dart`
- `lib/core/services/courier_location_service.dart`
- `lib/core/services/courier_notification_service.dart`

## 13.2 Tespit Edilen Hatalar

### HATA-CO1: Courier Service Eager Init
- **Dosya:** `lib/core/services/courier_request_service.dart`
- **Sorun:** Birden fazla service field olarak init ediliyor.

## 13.3 Supabase SQL Düzeltmeleri

```sql
-- =====================================================
-- DOSYA: supabase/migrations/20260728000011_courier_fixes.sql
-- AMAÇ: Courier RLS + location tracking
-- =====================================================

-- 1. Courier requests RLS
DROP POLICY IF EXISTS "Users can view own courier requests" ON courier_requests;
CREATE POLICY "Users can view own courier requests" ON courier_requests
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR courier_id = auth.uid());

DROP POLICY IF EXISTS "Couriers can update assigned requests" ON courier_requests;
CREATE POLICY "Couriers can update assigned requests" ON courier_requests
  FOR UPDATE TO authenticated
  USING (courier_id = auth.uid())
  WITH CHECK (courier_id = auth.uid());

-- 2. Location tracking - sadece son konum tutulur (privacy)
CREATE OR REPLACE FUNCTION upsert_courier_location(
  p_lat NUMERIC,
  p_lng NUMERIC,
  p_accuracy NUMERIC DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO courier_locations (courier_id, lat, lng, accuracy, updated_at)
  VALUES (auth.uid(), p_lat, p_lng, p_accuracy, NOW())
  ON CONFLICT (courier_id)
  DO UPDATE SET
    lat = EXCLUDED.lat,
    lng = EXCLUDED.lng,
    accuracy = EXCLUDED.accuracy,
    updated_at = NOW();
END;
$$;

REVOKE ALL FROM PUBLIC, anon;
GRANT EXECUTE TO authenticated;

-- 3. Eski location kayıtlarını temizle (24 saat)
DELETE FROM courier_locations
WHERE updated_at < NOW() - INTERVAL '24 hours';
```

---

# 14. NEWS (HABERLER)

## 14.1 Tespit Edilen Hatalar

### HATA-NE1: News RLS
- **Sorun:** Yeni sistem, RLS kontrolü gerekli.

## 14.2 Supabase SQL Düzeltmeleri

```sql
-- =====================================================
-- DOSYA: supabase/migrations/20260728000012_news_fixes.sql
-- AMAÇ: News RLS + published_at trigger (zaten var)
-- =====================================================

-- 1. News RLS
DROP POLICY IF EXISTS "Anyone can view published news" ON news;
CREATE POLICY "Anyone can view published news" ON news
  FOR SELECT TO anon, authenticated
  USING (is_published = TRUE AND published_at <= NOW());

DROP POLICY IF EXISTS "Admins manage all news" ON news;
CREATE POLICY "Admins manage all news" ON news
  FOR ALL TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- 2. News comments RLS
DROP POLICY IF EXISTS "Anyone can view news comments" ON news_comments;
CREATE POLICY "Anyone can view news comments" ON news_comments
  FOR SELECT TO anon, authenticated
  USING (is_deleted = FALSE);

DROP POLICY IF EXISTS "Authenticated users can comment" ON news_comments;
CREATE POLICY "Authenticated users can comment" ON news_comments
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- 3. News views tracking
CREATE TABLE IF NOT EXISTS news_views (
  news_id UUID NOT NULL REFERENCES news(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id),
  ip_address INET,
  viewed_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (news_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_news_views_news ON news_views (news_id);
```

---

# 🔧 UYGULAMA SIRASI

## Aşama 1: Kritik (Hemen - Bugün)

```bash
# 1. Supabase'de çalıştır
psql -h db.xsbukxkgtmdyickknqzf.supabase.co -U postgres -d postgres -f supabase/migrations/20260728000001_auth_fixes.sql
psql -h db.xsbukxkgtmdyickknqzf.supabase.co -U postgres -d postgres -f supabase/migrations/20260728000002_chat_rls_fixes.sql
psql -h db.xsbukxkgtmdyickknqzf.supabase.co -U postgres -d postgres -f supabase/migrations/20260728000003_market_fixes.sql
psql -h db.xsbukxkgtmdyickknqzf.supabase.co -U postgres -d postgres -f supabase/migrations/20260728000004_order_fixes.sql
psql -h db.xsbukxkgtmdyickknqzf.supabase.co -U postgres -d postgres -f supabase/migrations/20260728000006_storage_fixes.sql

# 2. Dart düzeltmeleri
# - chat_service.dart:682 mantık fix
# - order_service.dart:createOrder RPC kullan
# - product_service.dart:89 SQL injection fix
# - storage_service.dart:fileExists fix
# - main.dart signedIn event dedup
```

## Aşama 2: Orta (Bu Hafta)

```bash
# 1. Supabase
psql ... -f supabase/migrations/20260728000005_payment_fixes.sql
psql ... -f supabase/migrations/20260728000007_social_fixes.sql
psql ... -f supabase/migrations/20260728000008_admin_fixes.sql
psql ... -f supabase/migrations/20260728000009_notification_fixes.sql

# 2. Dart
# - ThemeProvider race condition fix
# - Login screen v1 cleanup
# - AuthService singleton
# - Error handler standardization
# - Eager init → lazy init tüm servislerde
```

## Aşama 3: İyileştirme (Bu Ay)

```bash
# 1. Supabase
psql ... -f supabase/migrations/20260728000010_smm_fixes.sql
psql ... -f supabase/migrations/20260728000011_courier_fixes.sql
psql ... -f supabase/migrations/20260728000012_news_fixes.sql

# 2. Dart
# - Crash reporting (Sentry/Crashlytics) entegrasyonu
# - Major paket güncellemeleri (google_mobile_ads, image_cropper, vb.)
# - Refactor: 28-parametreli metodlar
# - Performance: N+1 query düzeltmeleri
# - Test coverage artırma
```

---

# 📊 ÖZET

| Kategori | SQL Sayısı | Dart Fix Sayısı |
|----------|------------|-----------------|
| Auth | 1 | 3 |
| Chat | 1 | 3 |
| Market | 1 | 4 |
| Order | 1 | 4 |
| Payment/Wallet | 1 | 3 |
| Storage | 1 | 3 |
| Social | 1 | 2 |
| Admin | 1 | 1 |
| Theme | 0 | 2 |
| Main/Init | 0 | 3 |
| Notification | 1 | 1 |
| SMM | 1 | 1 |
| Courier | 1 | 1 |
| News | 1 | 0 |
| **TOPLAM** | **12 SQL** | **31 Dart fix** |

---

# ⚠️ ÖNEMLİ NOTLAR

1. **Migration'ları sırayla çalıştır**: Her migration bir öncekinin üzerine inşa ediyor.
2. **Production'da önce staging'de test et**.
3. **Yedek al**: `pg_dump` ile migration çalıştırmadan önce.
4. **Dart değişikliklerinden sonra** `flutter analyze` çalıştır.
5. **RLS değişikliklerinden sonra** Supabase anon key ile test et (auth olmadan SELECT çalışmamalı).
6. **Her migration dosyasını Supabase Dashboard > SQL Editor'de** tek tek çalıştır.

---

**Hazırlayan:** Claude (CizreApp Hata Analizi)
**Tarih:** 2026-07-28
**Toplam Modül:** 14
**Toplam Hata:** 47 (5 Kritik, 7 Orta, 35+ Düşük)
**Toplam SQL Migration:** 12 dosya
**Toplam Dart Düzeltme:** 31 nokta
