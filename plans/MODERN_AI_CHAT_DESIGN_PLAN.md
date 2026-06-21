# CizreApp Modern AI Chat Tasarım Planı

## 🎯 Proje Özeti

CizreApp uygulamasına Google Gemini tarzında modern bir AI sohbet arayüzü eklemek ve admin panelinde hazır prompt şablonları ile görsellerin yönetilmesini sağlamak.

---

## 📋 Görev 1: Modern AI Chat UI Tasarımı (Gemini Tarzı)

### 1.1 Tasarım Özellikleri

**Renk Paleti:**
- **Arka Plan:** Koyu gri/siyah gradient (`#1A1A2E` → `#16213E`)
- **Ana Renk:** Mor/violet gradient (`#7B2CBF` → `#9D4EDD`)
- **İkincil Renk:** Açık mor (`#E0AAFF`)
- **Metin:** Beyaz (`#FFFFFF`) ve açık gri (`#B8B8D1`)
- **Kartlar:** Yarı saydam koyu (`#252542` opacity 0.8)

**Tipografi:**
- Başlıklar: Bold, 18-24pt
- Mesajlar: Regular, 15-16pt
- Alt metin: Light, 12-13pt

**Köşe Yuvarlaklığı:**
- Kartlar: 20px border-radius
- Mesaj balonları: 16px border-radius
- Butonlar: 12px border-radius

### 1.2 Ekran Yapısı

```
┌─────────────────────────────────────┐
│  ← Geri    AI Asistan    ⋮ Menü    │  ← AppBar (gradient)
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐   │
│  │  🤖 AI Avatar                │   │
│  │  "Merhaba! Size nasıl       │   │  ← Hoşgeldin mesajı
│  │  yardımcı olabilirim?"      │   │
│  └─────────────────────────────┘   │
│                                     │
│                    ┌─────────────┐ │
│                    │ Kullanıcı    │ │  ← Kullanıcı mesajı (sağda)
│                    │ mesajı...   │ │
│                    └─────────────┘ │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  🤖 AI Yanıt               │   │
│  │  [Markdown içerik]         │   │
│  │  [Görsel gösterimi]        │   │
│  └─────────────────────────────┘   │
│                                     │
├─────────────────────────────────────┤
│  ┌───┐ ┌───────────────────────┐   │
│  │ 📷│ │ Mesaj yazın...       │ │   │  ← Mesaj girişi
│  └───┘ └───────────────────────┘   │
│                                     │
│  ┌─────┐┌─────┐┌─────┐┌─────┐     │
│  │ 📦  ││ 🍽️  ││ 🎯  ││ ✨  │     │  ← Hızlı prompt kartları
│  │List││Tarif││Plan ││Şiir │     │
│  └─────┘└─────┘└─────┘└─────┘     │
└─────────────────────────────────────┘
```

### 1.3 Bileşenler

#### 1.3.1 AI Hoşgeldin Kartı
- Yarı saydam kart tasarımı
- Gradient avatar ikonu
- Animasyonlu hoşgeldin mesajı
- Önerilen sorular listesi

#### 1.3.2 Mesaj Balonları
- **Kullanıcı:** Sağda, mor gradient arka plan
- **AI:** Solda, koyu kart arka plan, AI avatari ile

#### 1.3.3 Hızlı Prompt Kartları (Görsellı)
- Görsel thumbnail (üstte)
- Başlık (altında)
- Gradient hover efekti
- Tıklama animasyonu

#### 1.3.4 Mesaj Giriş Alanı
- Şeffaf arka plan
- Solunda medya ekleme butonu
- Yuvarlak köşeli text field
- Gönder butonu (gradient)

### 1.4 Animasyonlar
- Mesaj gönderme: Slide-up + fade-in
- AI yazıyor: Pulsing dots animasyonu
- Kart hover: Scale 1.02 + glow efekti
- Sayfa geçişi: Fade transitions

---

## 📋 Görev 2: Admin Panel - Yapay Zeka Yönetimi Sekmesi

### 2.1 Yeni Tab: "Hazır Promt'lar & Görseller"

```
┌────────────────────────────────────────────────────────────┐
│  ⚙️ Ayarlar  💬 Modeller  🔑 API  📊 İst.  💬 Sohbetler   │
│                                              🖼️ Promt'lar  │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ┌─ Promt Şablonları ──────┐  ┌─ Görsel Kütüphanesi ───┐ │
│  │ [+ Yeni Ekle] [Filtre ▼] │  │ [+ Görsel Yükle]       │ │
│  ├──────────────────────────┤  ├─────────────────────────┤ │
│  │ ┌────────────────────┐   │  │ ┌─────┐┌─────┐┌─────┐ │ │
│  │ │ 🖼️ [Görsel]        │   │  │ │     ││     ││     │ │ │
│  │ │                    │   │  │ │ img ││ img ││ img │ │ │
│  │ │ Alışveriş Listesi  │   │  │ │     ││     ││     │ │ │
│  │ │ Aktif ✓            │   │  │ └─────┘└─────┘└─────┘ │ │
│  │ └────────────────────┘   │  │ [kategori] [tag]      │ │
│  │ ┌────────────────────┐   │  │ ┌─────┐┌─────┐┌─────┐ │ │
│  │ │ 🖼️ [Görsel]        │   │  │ │     ││     ││     │ │ │
│  │ │                    │   │  │ │ img ││ img ││ img │ │ │
│  │ │ Yemek Tarifi       │   │  │ │     ││     ││     │ │ │
│  │ │ Aktif ✓            │   │  │ └─────┘└─────┘└─────┘ │ │
│  │ └────────────────────┘   │  └─────────────────────────┘ │
│  └──────────────────────────┘                               │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### 2.2 Özellikler

#### 2.2.1 Prompt Şablonu Yönetimi
- Görsel yükleme (thumbnail için)
- Başlık ve açıklama
- Prompt metni
- Sıralama (sort order)
- Aktif/Pasif toggle
- Kategori seçimi
- Önizleme

#### 2.2.2 Görsel Kütüphanesi
- Grid görünümü
- Sürükle-bırak sıralama
- Kategori/tag sistemi
- Arama filtresi
- Toplu silme
- Görsel önizleme (zoom)

---

## 📋 Görev 3: Veritabanı Değişiklikleri

### 3.1 Mevcut Tablo: `ai_quick_prompts`

```sql
-- Mevcut yapıya eklenecek alanlar:
ALTER TABLE ai_quick_prompts ADD COLUMN image_url TEXT;
ALTER TABLE ai_quick_prompts ADD COLUMN category TEXT DEFAULT 'general';
ALTER TABLE ai_quick_prompts ADD COLUMN thumbnail_color TEXT DEFAULT '#7B2CBF';
```

### 3.2 Yeni Tablo: `ai_prompt_images`

```sql
CREATE TABLE ai_prompt_images (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  image_url TEXT NOT NULL,
  thumbnail_url TEXT,
  category TEXT DEFAULT 'general',
  tags TEXT[], -- PostgreSQL array
  alt_text TEXT,
  width INTEGER,
  height INTEGER,
  file_size INTEGER,
  created_by UUID REFERENCES profiles(id),
  is_active BOOLEAN DEFAULT true,
  usage_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- RLS Policies
ALTER TABLE ai_prompt_images ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir
CREATE POLICY "Public read ai_prompt_images" ON ai_prompt_images
  FOR SELECT USING (is_active = true);

-- Sadece admin ekleyebilir/silebilir
CREATE POLICY "Admin full access ai_prompt_images" ON ai_prompt_images
  FOR ALL USING (auth.jwt() ->> 'role' = 'admin');
```

---

## 📋 Görev 4: Model ve Servis Güncellemeleri

### 4.1 AIQuickPrompt Modeli (Güncelleme)

```dart
class AIQuickPrompt {
  final String id;
  final String title;
  final String prompt;
  final String icon;
  final String color;
  final int sortOrder;
  final bool isActive;
  
  // YENİ ALANLAR:
  final String? imageUrl;       // Görsel URL
  final String? category;       // Kategori
  final String? thumbnailColor; // Thumbnail arka plan rengi
}
```

### 4.2 Yeni Model: AIPromptImage

```dart
class AIPromptImage {
  final String id;
  final String imageUrl;
  final String? thumbnailUrl;
  final String category;
  final List<String> tags;
  final String? altText;
  final int? width;
  final int? height;
  final int usageCount;
  final DateTime createdAt;
}
```

---

## 📋 Görev 5: Dosya Yapısı Değişiklikleri

```
lib/
├── features/
│   ├── ai_chat/
│   │   ├── screens/
│   │   │   ├── ai_chat_detail_screen.dart      (MODERNIZE EDİLECEK)
│   │   │   └── ai_chat_list_screen.dart
│   │   ├── widgets/
│   │   │   ├── modern_ai_chat_widget.dart        (YENİ)
│   │   │   ├── ai_welcome_card.dart             (YENİ)
│   │   │   ├── ai_message_bubble.dart           (YENİ)
│   │   │   ├── ai_quick_prompt_card.dart        (YENİ - Görsellı)
│   │   │   ├── ai_image_message.dart             (YENİ)
│   │   │   └── ai_typing_indicator.dart          (YENİ)
│   │   └── theme/
│   │       └── ai_chat_theme.dart               (YENİ)
│   │
│   └── admin/
│       ├── widgets/
│       │   ├── ai_management_content.dart        (GÜNCELLENECEK)
│       │   ├── ai_prompts_tab.dart               (YENİ)
│       │   ├── ai_images_library_tab.dart        (YENİ)
│       │   └── prompt_form_dialog.dart           (YENİ)
│       └── services/
│           └── ai_prompt_service.dart            (YENİ)
│
├── core/
│   └── models/
│       ├── ai_quick_prompt_model.dart           (GÜNCELLENECEK)
│       └── ai_prompt_image_model.dart            (YENİ)
│
└── supabase/
    └── migrations/
        ├── add_image_to_quick_prompts.sql
        └── create_ai_prompt_images.sql
```

---

## 📋 Görev 6: AI Chat Servisine Eklemeler

```dart
// AIChatService'e eklenecek metodlar:

class AIChatService {
  // ... mevcut metodlar ...

  // YENİ: Görsellı prompt kartları için
  Future<List<AIQuickPrompt>> getActiveQuickPromptsWithImages() async {
    // image_url'si olan ve olmayan promptları getir
    // Görsel yoksa thumbnail_color kullan
  }

  // YENİ: Görsel kütüphanesi işlemleri
  Future<String?> uploadPromptImage(File file, {String? category, List<String>? tags});
  Future<void> deletePromptImage(String id);
  Future<List<AIPromptImage>> getPromptImages({String? category, String? search});
  Future<void> updatePromptImageUsage(String id);
}
```

---

## 🎨 Görsel Tasarım Detayları

### 7.1 Modern AI Chat Tema Renkleri

```dart
class AIChatTheme {
  // Arka plan
  static const Color backgroundStart = Color(0xFF1A1A2E);
  static const Color backgroundEnd = Color(0xFF16213E);
  
  // Gradient renkler
  static const Color primaryGradientStart = Color(0xFF7B2CBF);
  static const Color primaryGradientEnd = Color(0xFF9D4EDD);
  
  // Kart renkleri
  static const Color cardBackground = Color(0xFF252542);
  static const Color cardBackgroundLight = Color(0xFF2D2D4A);
  
  // Metin renkleri
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB8B8D1);
  static const Color textMuted = Color(0xFF6B6B8D);
  
  // Mesaj balonları
  static const Color userBubbleColor = Color(0xFF7B2CBF);
  static const Color aiBubbleColor = Color(0xFF2D2D4A);
  
  // Özel renkler
  static const Color success = Color(0xFF4ADE80);
  static const Color error = Color(0xFFF87171);
  static const Color warning = Color(0xFFFBBF24);
}
```

### 7.2 Boyutlar ve Spacing

```dart
// Border radius
static const double radiusSmall = 8.0;
static const double radiusMedium = 12.0;
static const double radiusLarge = 16.0;
static const double radiusXLarge = 20.0;
static const double radiusRound = 24.0;

// Padding
static const double paddingXS = 4.0;
static const double paddingS = 8.0;
static const double paddingM = 12.0;
static const double paddingL = 16.0;
static const double paddingXL = 24.0;

// Mesaj balonu max genişlik
static const double messageMaxWidth = 320.0;

// Prompt kartı boyutları
static const double promptCardWidth = 140.0;
static const double promptCardHeight = 120.0;
static const double promptImageHeight = 60.0;
```

---

## 📱 Responsive Davranış

### 8.1 Mobil (Default)
- Tek sütun mesaj görünümü
- Yatay kaydırılabilir prompt kartları
- Tam genişlik mesaj girişi

### 8.2 Tablet
- Daha geniş mesaj balonları
- 2 sıra prompt kartları
- Yan panel olarak geçmiş

### 8.3 Desktop
- 600px max genişlik merkezlenmiş
- Yan panelde sohbet listesi
- Split view destekli

---

## 🚀 Uygulama Sırası

1. **Veritabanı migration'ları çalıştır**
   - `ai_quick_prompts` tablosuna yeni alanlar
   - `ai_prompt_images` tablosu oluştur

2. **Modelleri güncelle**
   - `AIQuickPrompt` modeli
   - `AIPromptImage` modeli (yeni)

3. **Tema dosyası oluştur**
   - `ai_chat_theme.dart`

4. **Widget'ları oluştur**
   - `ai_welcome_card.dart`
   - `ai_message_bubble.dart`
   - `ai_quick_prompt_card.dart` (görsellı)
   - `ai_image_message.dart`

5. **AI Chat Detail Screen'i yeniden tasarla**
   - Modern tema uygula
   - Yeni widget'ları entegre et

6. **Admin panel güncellemeleri**
   - Yeni tab: Prompt'lar & Görseller
   - Prompt form dialog
   - Görsel kütüphanesi

7. **Servis güncellemeleri**
   - `AIChatService` güncelle
   - `AIPromptService` oluştur (yeni)

---

## 📊 Başarı Kriterleri

- [ ] AI sohbet ekranı Gemini tarzı modern görünümde
- [ ] Koyu tema, mor/violet gradyanlar aktif
- [ ] Her prompt kartında görsel thumbnail görünüyor
- [ ] Admin panelde prompt yönetimi çalışıyor
- [ ] Admin panelde görsel kütüphanesi çalışıyor
- [ ] Görsel yükleme ve silme işlemleri çalışıyor
- [ ] Mobil ve tablet görünümler düzgün
- [ ] Animasyonlar akıcı çalışıyor

---

## ⏱️ Not

Bu plan "Code" modunda adım adım implement edilecektir. Her aşama tamamlandığında test edilecek ve sonraki aşamaya geçilecektir.
