# Flutter App Performance Optimization Plan

## 🎯 Hedef
Uygulamanın açılış ve yüklenme sürelerini minimize etmek

## 📊 Sorun Tespiti

### 1. Debug vs Release Mode
- **Debug mode**: Doğal olarak 5-10x daha yavaş
- **Test**: `flutter run --release` ile test edin
- Eğer release modda hızlıysa, sorun yok - normal davranış

### 2. Supabase Query Performance
```dart
// ❌ KÖTÜ: Tüm kolonları çekiyor
await _supabase.from('posts').select();

// ✅ İYİ: Sadece gerekli kolonları çek
await _supabase.from('posts').select('id, content, created_at, user_id');
```

### 3. RLS Policies
- ✅ Zaten optimize ettik: `(select auth.uid())` kullanımı
- ✅ Multiple permissive policies konsolide edildi

### 4. Image Loading
```dart
// ❌ KÖTÜ: Her seferinde ağdan yüklüyor
Image.network(url)

// ✅ İYİ: Cache kullanıyor
CachedNetworkImage(
  imageUrl: url,
  placeholder: (context, url) => CircularProgressIndicator(),
  errorWidget: (context, url, error) => Icon(Icons.error),
)
```

### 5. Pagination
```dart
// ❌ KÖTÜ: Tüm veriyi tek seferde çekiyor
await _supabase.from('posts').select();

// ✅ İYİ: Sayfalama kullan
await _supabase.from('posts').select()
  .range(0, 19)  // İlk 20 kayıt
  .order('created_at', ascending: false);
```

---

## 🚀 Hızlı İyileştirmeler (1-2 saat)

### A. İndex Ekle
```sql
-- Sık kullanılan sorgular için index
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);
CREATE INDEX IF NOT EXISTS idx_products_shop_id ON products(shop_id);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_participants ON conversations USING gin(participant_ids);
```

### B. Pagination Ekle
Ana feed'lerde (posts, products, shops) pagination kullan:
- İlk yüklemede: 20 öğe
- Scroll'da: +20 öğe yükle

### C. Lazy Loading
Resimleri lazy load et - `cached_network_image` paketi kullan

### D. Gereksiz Rebuild'leri Önle
```dart
// const constructor kullan
const Text('Hello')

// Key kullan
ListView.builder(
  key: PageStorageKey('my_list'),
  // ...
)
```

---

## 🎨 Orta Seviye İyileştirmeler (4-6 saat)

### A. Query Optimization
Her serviste `.select()` yerine spesifik kolonlar:
```dart
// ShopService.dart
.select('id, name, logo_url, rating, category_id, is_active')
```

### B. Join Queries
N+1 problemi önleme:
```dart
// ❌ KÖTÜ: Her post için ayrı user sorgusu
for (var post in posts) {
  final user = await getUser(post.userId);
}

// ✅ İYİ: Tek sorguda al
.select('*, profiles!user_id(id, full_name, avatar_url)')
```

### C. State Management
Provider yerine daha performanslı bir çözüm:
- Riverpod (önerilen)
- Bloc
- GetX

---

## 🔧 İleri Seviye İyileştirmeler (1-2 gün)

### A. Database Denormalization
Sık kullanılan veriler için denormalize et:
```sql
-- posts tablosuna user bilgisi ekle (cache)
ALTER TABLE posts 
ADD COLUMN user_name TEXT,
ADD COLUMN user_avatar TEXT;

-- Trigger ile güncel tut
CREATE TRIGGER update_post_user_cache ...
```

### B. Client-Side Caching
- SharedPreferences ile basit cache
- Hive/Isar ile local database
- Offline-first architecture

### C. Background Processing
- Compute isolate kullan (ağır işlemler için)
- Background fetch (veri önden yükle)

---

## 📱 Platform Optimizasyonları

### Android
```gradle
// android/app/build.gradle
android {
    buildTypes {
        release {
            shrinkResources true
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
        }
    }
}
```

### iOS
```
flutter build ios --release --split-debug-info=./debug-info
```

---

## 🧪 Test ve Ölçüm

### 1. Performance Overlay
```dart
void main() {
  runApp(
    MaterialApp(
      showPerformanceOverlay: true, // FPS göster
      home: MyApp(),
    ),
  );
}
```

### 2. Timeline
```bash
flutter run --profile --trace-startup
```

### 3. DevTools
```bash
flutter pub global activate devtools
flutter pub global run devtools
```

---

## ✅ Öncelikli Aksiyonlar

1. **Hemen Yapılacak:**
   - [ ] Release modda test et (`flutter run --release`)
   - [ ] Database index'leri ekle
   - [ ] `cached_network_image` paketi ekle
   - [ ] Ana feed'lerde pagination ekle (20 öğe)

2. **Bu Hafta:**
   - [ ] Query optimization (select specific columns)
   - [ ] Join queries ile N+1 problem çöz
   - [ ] Gereksiz rebuild'leri tespit et

3. **Gelecek Hafta:**
   - [ ] State management iyileştir
   - [ ] Client-side caching ekle
   - [ ] Background processing

---

## 📞 Sorun Devam Ederse

Eğer yukarıdaki iyileştirmelerden sonra hala yavaşsa:

1. **Network latency**: Supabase region kontrol et (en yakın server)
2. **Device performance**: Eski telefon mu? RAM yeterli mi?
3. **Data size**: Çok fazla veri mi var? (örn: 1000+ ürün)
4. **Memory leak**: `flutter analyze` ve DevTools ile kontrol

---

## 🎯 Beklenen Sonuçlar

- **Debug mode**: 2-3 saniye (kabul edilebilir)
- **Release mode**: <1 saniye (hedef)
- **FPS**: 60 (smooth scroll)
- **Memory**: <200MB (normal kullanım)
