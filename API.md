# CizreApp - API & Supabase Entegrasyonu Rehberi

## 🔌 Supabase RLS Politikaları

### Profiles Tablosu

```sql
-- Kullanıcılar kendi profillerini görebilir ve düzenleyebilir
CREATE POLICY "Users can view own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

-- Kullanıcılar kendi profilini güncelleyebilir
CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

-- Admin herkesin profilini görebilir
CREATE POLICY "Admin can view all profiles" ON profiles
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );
```

### Products Tablosu

```sql
-- Herkes ürünleri görebilir
CREATE POLICY "Anyone can view products" ON products
  FOR SELECT USING (true);

-- Satıcılar kendi ürünlerini ekleyebilir/düzenleyebilir
CREATE POLICY "Sellers can manage own products" ON products
  FOR ALL USING (
    shop_id IN (
      SELECT id FROM shops WHERE owner_id = auth.uid()
    )
  );

-- Admin tüm ürünleri yönetebilir
CREATE POLICY "Admin can manage all products" ON products
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );
```

### Orders Tablosu

```sql
-- Kullanıcılar kendi siparişlerini görebilir
CREATE POLICY "Users can view own orders" ON orders
  FOR SELECT USING (user_id = auth.uid());

-- Satıcılar kendi dükkanlarının siparişlerini görebilir
CREATE POLICY "Sellers can view own shop orders" ON orders
  FOR SELECT USING (
    shop_id IN (
      SELECT id FROM shops WHERE owner_id = auth.uid()
    )
  );

-- Admin tüm siparişleri görebilir
CREATE POLICY "Admin can view all orders" ON orders
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );
```

### Messages Tablosu

```sql
-- Kullanıcılar sadece kendi mesajlarını görebilir
CREATE POLICY "Users can view own messages" ON messages
  FOR SELECT USING (
    sender_id = auth.uid() OR 
    EXISTS (
      SELECT 1 FROM conversations 
      WHERE id = conversation_id 
      AND (user_id = auth.uid() OR other_user_id = auth.uid())
    )
  );

-- Kullanıcılar mesaj gönderebilir
CREATE POLICY "Users can send messages" ON messages
  FOR INSERT WITH CHECK (sender_id = auth.uid());
```

---

## 🔄 Service Fonksiyonları

### Market Service

```dart
// lib/features/market/services/market_service.dart

// Kategorileri getir
Future<List<Category>> getCategories()

// Dükkanları getir (filtrelenmiş)
Future<List<Shop>> getShops({
  required String? categoryId,
  String? searchQuery,
  double? maxDistance,
})

// Ürünleri getir
Future<List<Product>> getProducts({
  required String shopId,
  int limit = 20,
  int offset = 0,
})

// Ürün detaylarını getir
Future<Product?> getProductDetail(String productId)

// En çok satılan ürünleri getir
Future<List<Product>> getTopProducts()
```

### Social Service

```dart
// lib/features/social/services/post_service.dart

// Gönderi oluştur
Future<Post?> createPost({
  required String userId,
  required String content,
  List<String>? imageUrls,
  String? location,
})

// Gönderileri getir (feed)
Future<List<Post>> getPosts({
  int limit = 20,
  int offset = 0,
})

// Gönderi beğen/beğenmekten çık
Future<void> toggleLike(String postId)

// Yorum ekle
Future<Comment?> addComment({
  required String postId,
  required String content,
})

// Takip et/Takipten çık
Future<void> toggleFollow(String userId)
```

### Shop Service

```dart
// lib/features/shop/services/order_service.dart

// Sipariş oluştur
Future<Order?> createOrder({
  required String userId,
  required String shopId,
  required List<OrderItem> items,
  required String deliveryAddress,
  required PaymentMethod paymentMethod,
})

// Siparişleri getir
Future<List<Order>> getOrders({
  String? userId,
  String? shopId,
  OrderStatus? status,
})

// Sipariş durumunu güncelle
Future<void> updateOrderStatus({
  required String orderId,
  required OrderStatus status,
})

// Sipariş takibi
Stream<Order> watchOrder(String orderId)
```

### Chat Service

```dart
// lib/features/chat/services/chat_service.dart

// Konuşma al/oluştur
Future<Conversation?> getOrCreateConversation(String otherUserId)

// Konuşmaları listele
Future<List<Conversation>> getConversations()

// Mesajları getir
Future<List<Message>> getMessages(String conversationId)

// Mesaj gönder
Future<Message?> sendMessage({
  required String conversationId,
  required String content,
})

// Mesajları okundu olarak işaretle
Future<void> markMessagesAsRead(String conversationId)

// Gerçek zamanlı mesajlar
Stream<List<Message>> subscribeToMessages(String conversationId)
```

---

## 📊 Supabase Sorguları Örnekleri

### Kategori Listesi

```sql
SELECT * FROM categories 
WHERE parent_id IS NULL 
ORDER BY display_order ASC;
```

### Dükkan Ara (Konum Tabanlı)

```sql
SELECT 
  s.*,
  p.rating,
  p.review_count,
  ROUND(
    (6371 * ACOS(
      COS(RADIANS(37.7749)) * COS(RADIANS(s.latitude)) *
      COS(RADIANS(s.longitude) - RADIANS(-122.4194)) +
      SIN(RADIANS(37.7749)) * SIN(RADIANS(s.latitude))
    )) * 1000
  ) AS distance_meters
FROM shops s
LEFT JOIN profiles p ON s.owner_id = p.id
WHERE s.is_active = true
ORDER BY distance_meters ASC
LIMIT 20;
```

### Top Satıcılar

```sql
SELECT 
  s.id,
  s.name,
  COUNT(DISTINCT o.id) as total_orders,
  AVG(p.rating) as avg_rating,
  SUM(o.total_amount) as total_revenue
FROM shops s
LEFT JOIN orders o ON s.id = o.shop_id
LEFT JOIN profiles p ON s.owner_id = p.id
WHERE s.is_active = true
GROUP BY s.id
ORDER BY avg_rating DESC, total_orders DESC
LIMIT 10;
```

### Kullanıcı İstatistikleri

```sql
SELECT 
  u.id,
  u.username,
  COUNT(DISTINCT o.id) as total_orders,
  SUM(o.total_amount) as total_spent,
  COUNT(DISTINCT f.following_id) as following_count,
  COUNT(DISTINCT followers.follower_id) as follower_count
FROM profiles u
LEFT JOIN orders o ON u.id = o.user_id
LEFT JOIN follows f ON u.id = f.follower_id
LEFT JOIN follows followers ON u.id = followers.following_id
WHERE u.id = $1
GROUP BY u.id;
```

### Son Siparişler (Admin)

```sql
SELECT 
  o.id,
  o.order_number,
  u.username as customer_name,
  s.name as shop_name,
  o.total_amount,
  o.status,
  o.created_at
FROM orders o
JOIN profiles u ON o.user_id = u.id
JOIN shops s ON o.shop_id = s.id
ORDER BY o.created_at DESC
LIMIT 50;
```

---

## 🔐 Supabase Auth Entegrasyonu

### Kayıt

```dart
Future<void> register({
  required String email,
  required String password,
  required String username,
  required UserRole role,
}) async {
  final response = await supabase.auth.signUp(
    email: email,
    password: password,
  );

  if (response.user != null) {
    await supabase.from('profiles').insert({
      'id': response.user!.id,
      'username': username,
      'email': email,
      'role': role.toString().split('.').last.toLowerCase(),
    });
  }
}
```

### Giriş

```dart
Future<void> login({
  required String email,
  required String password,
}) async {
  await supabase.auth.signInWithPassword(
    email: email,
    password: password,
  );
}
```

### Oturum Kontrol

```dart
final user = supabase.auth.currentUser;
if (user != null) {
  // Kullanıcı giriş yapmış
  final profile = await supabase
    .from('profiles')
    .select()
    .eq('id', user.id)
    .single();
}
```

---

## 📱 Gerçek Zamanlı Özellikler

### Siparişi Takip Et

```dart
supabase
  .from('orders')
  .stream(primaryKey: ['id'])
  .eq('id', orderId)
  .listen((event) {
    final order = Order.fromJson(event[0]);
    print('Sipariş durumu: ${order.status}');
  });
```

### Mesajları Dinle

```dart
supabase
  .from('messages')
  .stream(primaryKey: ['id'])
  .eq('conversation_id', conversationId)
  .listen((event) {
    final messages = event
      .map((json) => Message.fromJson(json))
      .toList();
    setState(() => _messages = messages);
  });
```

### Profil Güncellemelerini Dinle

```dart
supabase
  .from('profiles')
  .stream(primaryKey: ['id'])
  .eq('id', userId)
  .listen((event) {
    final profile = UserModel.fromJson(event[0]);
    print('Profil güncellendi: ${profile.username}');
  });
```

---

## 🆔 Veri Modelleri

### User Model

```dart
class UserModel {
  final String id;
  final String username;
  final String? email;
  final UserRole role;
  final String? avatarUrl;
  final String? bio;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.username,
    this.email,
    required this.role,
    this.avatarUrl,
    this.bio,
    required this.createdAt,
  });
}
```

### Shop Model

```dart
class Shop {
  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? bannerUrl;
  final double latitude;
  final double longitude;
  final String? workingHours;
  final bool isActive;
  final DateTime createdAt;

  Shop({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    this.logoUrl,
    this.bannerUrl,
    required this.latitude,
    required this.longitude,
    this.workingHours,
    required this.isActive,
    required this.createdAt,
  });
}
```

### Order Model

```dart
class Order {
  final String id;
  final String orderNumber;
  final String userId;
  final String shopId;
  final List<OrderItem> items;
  final double totalAmount;
  final OrderStatus status;
  final String deliveryAddress;
  final PaymentMethod paymentMethod;
  final DateTime createdAt;

  Order({
    required this.id,
    required this.orderNumber,
    required this.userId,
    required this.shopId,
    required this.items,
    required this.totalAmount,
    required this.status,
    required this.deliveryAddress,
    required this.paymentMethod,
    required this.createdAt,
  });
}
```

---

## 🔄 Veri Senkronizasyonu

### Local Cache

```dart
// Önce cache'den al, sonra server'dan senkronize et
Future<List<Product>> getProductsCached(String shopId) async {
  final cached = await _cacheService.getProducts(shopId);
  
  if (cached != null && cached.isNotEmpty) {
    return cached;
  }
  
  final fresh = await getProducts(shopId);
  await _cacheService.saveProducts(shopId, fresh);
  
  return fresh;
}
```

### Çevrimdışı Destek

```dart
Future<void> syncPendingOrders() async {
  final pending = await _cacheService.getPendingOrders();
  
  for (var order in pending) {
    try {
      await createOrder(
        userId: order.userId,
        items: order.items,
        shopId: order.shopId,
      );
      await _cacheService.removePendingOrder(order.id);
    } catch (e) {
      print('Senkronizasyon hatası: $e');
    }
  }
}
```

---

## ⚙️ Webhooks (Gelecek)

### Sipariş Durumu Değiştiğinde Bildirim

```
POST /webhooks/order-status-changed
{
  "order_id": "123",
  "new_status": "delivered",
  "timestamp": "2024-01-21T12:00:00Z"
}
```

### Yeni Mesaj Bildirimi

```
POST /webhooks/message-received
{
  "conversation_id": "456",
  "sender_id": "user1",
  "message": "Merhaba",
  "timestamp": "2024-01-21T12:00:00Z"
}
```

---

## 📈 Performans İpuçları

### Sayfalama Kullanın

```dart
// İyi - Sayfalama ile sınırlı veri
const pageSize = 20;
final page = 0;

final products = await supabase
  .from('products')
  .select()
  .range(page * pageSize, (page + 1) * pageSize - 1);

// Kötü - Tüm verileri bir seferde al
final allProducts = await supabase
  .from('products')
  .select();
```

### İndeks Kullanın

```sql
-- Sık aradığınız alanlar için index oluşturun
CREATE INDEX idx_products_shop_id ON products(shop_id);
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_posts_created_at ON posts(created_at DESC);
```

### Seçilen Sütunlar

```dart
// İyi - Sadece gerekli sütunlar
final users = await supabase
  .from('profiles')
  .select('id, username, avatar_url')
  .limit(10);

// Kötü - Tüm sütunlar (gereksiz veri)
final users = await supabase
  .from('profiles')
  .select()
  .limit(10);
```

---

## 🆘 Yaygın Hatalar ve Çözümleri

### 1. RLS Policy Error

```
Error: row-level security policy perm_read_public does not exist
```

**Çözüm**: RLS politikasını kontrol edin ve yeniden oluşturun.

### 2. Foreign Key Violation

```
Error: insert or update on table "orders" violates foreign key constraint
```

**Çözüm**: İlgili kayıtların var olduğundan emin olun.

### 3. Timeout Error

```
Error: Connection timeout
```

**Çözüm**: Sayfalama kullanın, aşırı veri sorgusu yapan sorguları optimize edin.

### 4. Duplicate Key Error

```
Error: duplicate key value violates unique constraint
```

**Çözüm**: Benzersiz alanları kontrol edin (email, username vb.)

---

**Başarılar! 🚀**

Daha fazla bilgi için [Supabase Dokümantasyonu](https://supabase.com/docs) ziyaret edin.
