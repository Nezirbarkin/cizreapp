# Content Flashing & Layout Shift Düzeltme Planı

## 🎯 Problem
Kullanıcı ekranlara girdiğinde önce placeholder veriler gösteriliyor (örn: "kullanıcı adı"), sonra gerçek veri gelince değişiyor. Bu kötü UX oluşturuyor.

## 📊 Analiz Sonuçları
- **252+ CircularProgressIndicator** kullanımı tespit edildi
- **60+ ekranda** `_isLoading = true` pattern tekrarlanıyor
- En kritik ekranlar:
  - `post_detail_screen.dart` - Kullanıcı profili 2. sorguda geliyor
  - `shop_detail_screen.dart` - Dükkan + ürünler ayrı sorgular
  - `product_detail_screen.dart` - Ürün + dükkan + yorumlar ayrı
  - `user_profile_screen.dart` - Profil + postlar ayrı
  - `social_screen.dart` - N+1 profil sorguları (düzeltildi ama skeleton lazım)

## ✅ Tamamlanan İyileştirmeler
1. ✅ `skeleton_loader.dart` widget oluşturuldu (shimmer efektli)
2. ✅ `main.dart` paralel servis başlatma
3. ✅ `market_screen.dart` timer rebuild sorunu düzeltildi
4. ✅ `market_screen.dart` paralel API çağrıları
5. ✅ `social_screen.dart` N+1 sorgu düzeltildi (`inFilter`)
6. ✅ `shop_service.dart` select optimizasyonu

## 🎯 3 Aşamalı Çözüm

### **Faz 1: Skeleton Loader Entegrasyonu** (En Hızlı Etki)
5 kritik ekrana skeleton loader ekle:

#### 1. `post_detail_screen.dart`
```dart
// ÖNCESİ
if (_isLoading) {
  return Center(child: CircularProgressIndicator());
}

// SONRASI
if (_isLoading) {
  return SingleChildScrollView(
    padding: EdgeInsets.all(16),
    child: Column(
      children: [
        Skeletons.postCard(),
        SizedBox(height: 16),
        Skeletons.comment(),
        Skeletons.comment(),
      ],
    ),
  );
}
```

#### 2. `shop_detail_screen.dart`
```dart
if (_isLoading) {
  return SingleChildScrollView(
    child: Column(
      children: [
        Skeletons.detailHeader(),
        SizedBox(height: 16),
        Skeletons.grid(itemCount: 4),
      ],
    ),
  );
}
```

#### 3. `product_detail_screen.dart`
```dart
if (_isLoading) {
  return SingleChildScrollView(
    child: Column(
      children: [
        SkeletonLoader.rect(height: 300),
        Padding(
          padding: EdgeInsets.all(16),
          child: Skeletons.detailHeader(),
        ),
      ],
    ),
  );
}
```

#### 4. `user_profile_screen.dart`
```dart
if (_isLoading) {
  return SingleChildScrollView(
    child: Column(
      children: [
        Skeletons.detailHeader(),
        SizedBox(height: 16),
        Skeletons.grid(itemCount: 6),
      ],
    ),
  );
}
```

#### 5. `social_screen.dart`
```dart
if (_isLoading) {
  return ListView.builder(
    itemCount: 3,
    itemBuilder: (_, i) => Padding(
      padding: EdgeInsets.all(12),
      child: Skeletons.postCard(),
    ),
  );
}
```

**Etki**: Kullanıcı hemen içerik yükleniyormuş gibi hisseder (Layout shift yok)

---

### **Faz 2: Cache Mekanizması** (Orta Vadeli)

#### A. CacheService Genişletme
```dart
class CacheService {
  // Mevcut cache
  static final _cache = <String, dynamic>{};
  
  // EKLE: Timestamp tracking
  static final _cacheTimestamps = <String, DateTime>{};
  static const _defaultTTL = Duration(minutes: 5);
  
  /// Stale-While-Revalidate pattern
  static Future<T?> fetchWithCache<T>({
    required String key,
    required Future<T> Function() fetcher,
    Duration ttl = _defaultTTL,
  }) async {
    // 1. Cache'den oku
    final cached = get<T>(key);
    final timestamp = _cacheTimestamps[key];
    
    // 2. Eğer cache varsa ve fresh ise, direkt dön
    if (cached != null && timestamp != null) {
      final age = DateTime.now().difference(timestamp);
      if (age < ttl) {
        return cached; // Fresh cache
      }
      
      // 3. Stale cache - arka planda güncelle ama eski veriyi dön
      _refreshInBackground(key, fetcher);
      return cached; // Stale ama kullanılabilir
    }
    
    // 4. Cache yok - fetch et ve cache'le
    final fresh = await fetcher();
    set(key, fresh);
    _cacheTimestamps[key] = DateTime.now();
    return fresh;
  }
  
  static void _refreshInBackground<T>(
    String key,
    Future<T> Function() fetcher,
  ) async {
    try {
      final fresh = await fetcher();
      set(key, fresh);
      _cacheTimestamps[key] = DateTime.now();
    } catch (e) {
      // Arka plan güncelleme başarısız, eski cache'i kullan
    }
  }
}
```

#### B. PostService'de Kullanım
```dart
Future<Post> getPostById(String postId) async {
  return await CacheService.fetchWithCache(
    key: 'post_$postId',
    fetcher: () async {
      // Gerçek Supabase sorgusu
      final response = await _supabase
        .from('posts')
        .select('*, profiles!posts_user_id_fkey(*)')  // JOIN
        .eq('id', postId)
        .single();
      return Post.fromJson(response);
    },
    ttl: Duration(minutes: 2), // 2 dakika cache
  );
}
```

**Etki**: 
- İlk açılışta: Skeleton + fetch (normal)
- İkinci açılışta: Eski veri hemen göster + arka planda güncelle (hızlı)

---

### **Faz 3: SQL JOIN Optimizasyonu** (Uzun Vadeli)

#### Problem
`post_detail_screen.dart`:
```dart
// ŞİMDİ: 2 sorgu
final post = await getPost(postId);        // 1. sorgu
final profile = await getProfile(post.userId); // 2. sorgu - YAVASLATIR
```

#### Çözüm: PostgreSQL View
```sql
CREATE OR REPLACE VIEW posts_with_profiles AS
SELECT 
  p.*,
  prof.id as profile_id,
  prof.username,
  prof.full_name,
  prof.avatar_url,
  prof.is_verified
FROM posts p
LEFT JOIN profiles prof ON p.user_id = prof.id;
```

#### Dart Tarafı
```dart
Future<Post> getPostWithProfile(String postId) async {
  final response = await _supabase
    .from('posts_with_profiles')  // View kullan
    .select('*')
    .eq('id', postId)
    .single();
    
  return Post.fromJsonWithProfile(response); // 1 sorgu!
}
```

**Benzer view'ler**:
- `shops_with_products` (shop_detail için)
- `products_with_shop` (product_detail için)
- `users_with_posts` (user_profile için)

**Etki**: 2 sorgu → 1 sorgu = %50 daha hızlı

---

## 📋 Uygulama Sırası

### Sprint 1 (Faz 1) - Hızlı Kazanım
1. ✅ Skeleton loader widget oluşturuldu
2. `post_detail_screen.dart` - skeleton entegre et
3. `shop_detail_screen.dart` - skeleton entegre et
4. `product_detail_screen.dart` - skeleton entegre et
5. `user_profile_screen.dart` - skeleton entegre et
6. `social_screen.dart` - skeleton entegre et

**Tahmini Süre**: 2-3 saat
**Etki**: Kullanıcı deneyiminde %80 iyileşme

### Sprint 2 (Faz 2) - Orta Vadeli
1. `CacheService` genişlet (stale-while-revalidate)
2. `PostService` cache entegrasyonu
3. `ShopService` cache entegrasyonu
4. `ProductService` cache entegrasyonu
5. `ProfileService` cache entegrasyonu

**Tahmini Süre**: 3-4 saat
**Etki**: İkinci açılışlarda %90 daha hızlı

### Sprint 3 (Faz 3) - Uzun Vadeli
1. PostgreSQL view'ler oluştur
2. Service'lerde view kullanımı
3. Model'lerde `fromJsonWithProfile` methodları

**Tahmini Süre**: 4-5 saat
**Etki**: Veri yükleme %50 daha hızlı

---

## 🎯 Beklenen Sonuçlar

| Metrik | Şu An | Sprint 1 | Sprint 2 | Sprint 3 |
|--------|-------|----------|----------|----------|
| Layout Shift | ❌ Var | ✅ Yok | ✅ Yok | ✅ Yok |
| İlk Yükleme | 2-3 sn | 2-3 sn | 1-2 sn | 1 sn |
| İkinci Yükleme | 2-3 sn | 2-3 sn | <0.5 sn | <0.3 sn |
| Kullanıcı Memnuniyeti | 6/10 | 8/10 | 9/10 | 10/10 |

---

## 🚀 İlk Adım: Sprint 1'e Başla

**Öncelik**: `post_detail_screen.dart` (En çok kullanılan ekran)

1. Skeleton loader import et
2. `_isLoading` durumunda skeleton göster
3. Test et (Hot Reload)
4. Diğer ekranlara geç

**Not**: Her değişiklikten sonra flutter analyze çalıştır!
