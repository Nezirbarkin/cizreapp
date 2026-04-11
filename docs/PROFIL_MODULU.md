# Profil Modülü - Gerçek Veri Entegrasyonu

## 📋 Genel Bakış

CizreApp profil modülü, kullanıcıların profillerini görüntülemelerine, düzenlemelerine ve sosyal etkileşimde bulunmalarına olanak tanır. Bu modül gerçek Supabase verileriyle tam entegre çalışmaktadır.

## ✨ Özellikler

### 1. **Profil Görüntüleme** 
- ✅ Kullanıcı profil bilgileri (ad, bio, website, konum)
- ✅ Avatar (profil fotoğrafı)
- ✅ Kapak fotoğrafı
- ✅ İstatistikler (gönderi, takipçi, takip sayıları)
- ✅ Kullanıcının gönderileri
- ✅ Beğenilen gönderiler
- ✅ Kaydedilmiş gönderiler

### 2. **Profil Düzenleme**
- ✅ Ad soyad güncelleme
- ✅ Bio (hakkında) düzenleme
- ✅ Website URL ekleme
- ✅ Konum belirleme
- ✅ Avatar yükleme
- ✅ Kapak fotoğrafı yükleme

### 3. **Sosyal Etkileşim**
- ✅ Gönderi beğenme/beğenmekten vazgeçme
- ✅ Gönderi kaydetme/kaydetme kaldırma
- ✅ Takip etme/takipten çıkma
- ✅ Yorum yapma (post detail)
- ✅ Gönderi paylaşma

### 4. **Modern UI/UX**
- ✅ Instagram + Twitter hybrid tasarım
- ✅ Animated gradient background
- ✅ Glassmorphism efektleri
- ✅ Smooth animations
- ✅ Pull-to-refresh
- ✅ Responsive layout

## 📁 Dosya Yapısı

```
lib/features/profile/
├── screens/
│   ├── profile_screen.dart          # Ana profil ekranı
│   └── edit_profile_screen.dart     # Profil düzenleme ekranı
├── services/
│   └── profile_service.dart         # Profil işlemleri servisi
└── models/
    └── (Genel core/models kullanılıyor)
```

## 🔧 Servisler

### ProfileService

```dart
class ProfileService {
  // Profil bilgilerini çek
  Future<Map<String, dynamic>> getUserProfile(String userId)
  
  // Kullanıcının gönderilerini çek
  Future<List<Map<String, dynamic>>> getUserPosts(String userId)
  
  // Kaydettiği gönderileri çek
  Future<List<Map<String, dynamic>>> getSavedPosts(String userId)
  
  // Takip et/takipten çık
  Future<bool> toggleFollow(String targetUserId)
  
  // Takip durumunu kontrol et
  Future<bool> isFollowing(String targetUserId)
  
  // Gönderiyi beğen/beğenmekten vazgeç
  Future<bool> toggleLike(String postId)
  
  // Gönderiyi kaydet/kaydı kaldır
  Future<bool> toggleSave(String postId)
  
  // Profil fotoğrafı yükle
  Future<String?> uploadProfilePhoto(String filePath)
  
  // Kapak fotoğrafı yükle
  Future<String?> uploadCoverPhoto(String filePath)
  
  // Profili güncelle
  Future<bool> updateProfile({...})
  
  // Story'leri çek
  Future<List<Map<String, dynamic>>> getUserStories(String userId)
  
  // Story görüntüleme kaydet
  Future<void> viewStory(String storyId)
}
```

## 🎯 Kullanım Örnekleri

### Profil Sayfasına Gitme

```dart
// Kendi profilini görüntüleme
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const ProfileScreen(),
  ),
);

// Başka kullanıcının profilini görüntüleme
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => ProfileScreen(userId: 'user_id'),
  ),
);
```

### Profil Düzenleme

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const EditProfileScreen(),
  ),
);
```

### Gönderi Beğenme

```dart
final profileService = ProfileService();
await profileService.toggleLike(postId);
```

### Takip Etme

```dart
final profileService = ProfileService();
await profileService.toggleFollow(targetUserId);
```

## 🗄️ Veritabanı Şeması

### Profiles Tablosu

```sql
profiles (
  id UUID PRIMARY KEY,
  username TEXT UNIQUE,
  full_name TEXT,
  bio TEXT,
  avatar_url TEXT,
  cover_url TEXT,
  website TEXT,
  location TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
)
```

### Posts Tablosu

```sql
posts (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES profiles(id),
  content TEXT,
  image_url TEXT,
  created_at TIMESTAMP
)
```

### Post Likes Tablosu

```sql
post_likes (
  id UUID PRIMARY KEY,
  post_id UUID REFERENCES posts(id),
  user_id UUID REFERENCES profiles(id),
  created_at TIMESTAMP,
  UNIQUE(post_id, user_id)
)
```

### Post Saves Tablosu

```sql
post_saves (
  id UUID PRIMARY KEY,
  post_id UUID REFERENCES posts(id),
  user_id UUID REFERENCES profiles(id),
  created_at TIMESTAMP,
  UNIQUE(post_id, user_id)
)
```

### Follows Tablosu

```sql
follows (
  id UUID PRIMARY KEY,
  follower_id UUID REFERENCES profiles(id),
  following_id UUID REFERENCES profiles(id),
  created_at TIMESTAMP,
  UNIQUE(follower_id, following_id)
)
```

### Stories Tablosu

```sql
stories (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES profiles(id),
  media_url TEXT,
  media_type TEXT,
  duration INT,
  created_at TIMESTAMP,
  expires_at TIMESTAMP
)
```

### Story Views Tablosu

```sql
story_views (
  id UUID PRIMARY KEY,
  story_id UUID REFERENCES stories(id),
  user_id UUID REFERENCES profiles(id),
  created_at TIMESTAMP,
  UNIQUE(story_id, user_id)
)
```

## 🔐 Row Level Security (RLS)

### Profiles
```sql
-- Herkes profilleri okuyabilir
CREATE POLICY "Profiles are viewable by everyone"
  ON profiles FOR SELECT
  USING (true);

-- Sadece kendi profilini güncelleyebilir
CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE
  USING (auth.uid() = id);
```

### Posts
```sql
-- Herkes postları okuyabilir
CREATE POLICY "Posts are viewable by everyone"
  ON posts FOR SELECT
  USING (true);

-- Sadece kendi postunu silebilir
CREATE POLICY "Users can delete own posts"
  ON posts FOR DELETE
  USING (auth.uid() = user_id);
```

### Follows
```sql
-- Herkes takip ilişkilerini görebilir
CREATE POLICY "Follows are viewable by everyone"
  ON follows FOR SELECT
  USING (true);

-- Sadece kendi takiplerini ekleyebilir/silebilir
CREATE POLICY "Users can manage own follows"
  ON follows FOR ALL
  USING (auth.uid() = follower_id);
```

## 🎨 UI Komponenleri

### 1. Modern Header
- Animated gradient background
- Glass effect overlay
- Animated avatar with elastic bounce
- Username badge with verified icon
- Bio display

### 2. Stats Cards
- Staggered animation
- Icon + Count + Label layout
- Gradient dividers
- Glassmorphic container

### 3. Action Buttons
- Primary gradient button
- Secondary outlined buttons
- Icon buttons with ripple effect

### 4. Posts List
- Twitter-style compact cards
- Avatar on left, content on right
- Interactive action buttons
- Pull-to-refresh support

### 5. Empty States
- Icon with primary color
- Title and subtitle
- Centered layout

## 📱 Ekran Görüntüleri

### Profil Ekranı
```
┌─────────────────────────────────┐
│   [Animated Gradient Header]    │
│        [Profile Avatar]          │
│       FULL NAME                  │
│       @username ✓                │
│         Bio text                 │
├─────────────────────────────────┤
│ [📊 125]  [👥 1.2K]  [👤 456]  │
│  Posts    Followers   Following  │
│                                   │
│ [Profili Düzenle] [📤] [⚙️]    │
├─────────────────────────────────┤
│ [Gönderiler] [Beğeni] [Kayıtlı]│
├─────────────────────────────────┤
│ 👤 User Name ✓ @username · 1g  │
│    Post content here...          │
│    [Post Image]                  │
│    💬 5  🔁 23  ❤️ 124  🔖    │
├─────────────────────────────────┤
│ 👤 User Name ✓ @username · 2g  │
│    Another post...               │
└─────────────────────────────────┘
```

### Profil Düzenleme Ekranı
```
┌─────────────────────────────────┐
│ ← Profili Düzenle      ✓ Kaydet│
├─────────────────────────────────┤
│    [Cover Photo Section]         │
│    [Camera Button Overlay]       │
├─────────────────────────────────┤
│         [Profile Avatar]         │
│         [Camera Button]          │
├─────────────────────────────────┤
│ Ad Soyad                         │
│ [Input Field]                    │
│                                   │
│ Hakkında                         │
│ [Multiline Input]                │
│                                   │
│ Web Sitesi                       │
│ [URL Input]                      │
│                                   │
│ Konum                            │
│ [Location Input]                 │
│                                   │
│ [Değişiklikleri Kaydet Button]  │
└─────────────────────────────────┘
```

## 🚀 Performans Optimizasyonları

1. **Optimistic Updates**: Beğeni ve kaydetme işlemleri için anında UI güncellemesi
2. **Image Caching**: Network görsellerinin önbelleklenmesi
3. **Lazy Loading**: Listelerde sadece görünen itemların yüklenmesi
4. **Pull-to-Refresh**: Manuel veri yenileme
5. **Error Handling**: Hata durumlarında fallback UI

## 🐛 Bilinen Sınırlamalar

1. Beğenilen gönderiler sekmesi henüz doldurulmadı (backend query gerekli)
2. Story görüntüleme UI'ı yapılacak
3. Profil paylaşma özelliği eklenmedi
4. Mesajlaşma entegrasyonu tamamlanmadı

## 📝 Gelecek Geliştirmeler

- [ ] Story viewer ekranı
- [ ] Beğenilen gönderiler listesi
- [ ] Takipçi/Takip edilen listeleri
- [ ] Profil QR kodu
- [ ] Profil istatistik grafikleri
- [ ] Hesap gizliliği ayarları
- [ ] Engelleme özelliği
- [ ] Kullanıcı doğrulanma badge sistemi

## 🔗 İlgili Modüller

- **Social Module**: Post oluşturma ve paylaşma
- **Chat Module**: Mesajlaşma
- **Auth Module**: Kullanıcı kimlik doğrulama
- **Settings Module**: Uygulama ayarları

## 📚 Referanslar

- [Supabase Storage Docs](https://supabase.com/docs/guides/storage)
- [Flutter Image Picker](https://pub.dev/packages/image_picker)
- [Flutter Animations](https://flutter.dev/docs/development/ui/animations)

---

**Son Güncelleme**: 21 Ocak 2026
**Versiyon**: 1.0.0
**Durum**: ✅ Tamamlandı (Gerçek verilerle entegre)
