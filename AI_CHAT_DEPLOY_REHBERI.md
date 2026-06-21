# CizreApp AI Chat - Deployment Rehberi

## ÖNEMLİ: SQL Migration'ları Çalıştırın!

**Edge Function hatası alıyorsanız, muhtemelen tablolar oluşturulmamış.**

### Çalıştırılacak SQL Dosyaları:

1. **Supabase Dashboard** → **SQL Editor** sekmesi
2. Aşağıdaki iki SQL'i **sırasıyla** çalıştırın:

#### SQL 1: `AI_CHAT_DEPLOY_REHBERI.md` içindeki ilk SQL (API anahtarı kolonları)

#### SQL 2: `supabase/migrations/create_ai_chat_tables.sql` (tablolar ve RLS)

---

## 1. Veritabanı Migration'ı

### 1.1 Supabase SQL Editor'e Git
1. [Supabase Dashboard](https://supabase.com/dashboard) → Projenizi seçin
2. **SQL Editor** sekmesine tıklayın
3. Yeni bir sorgu oluşturun

### 1.2 SQL'i Çalıştırın
Aşağıdaki SQL'i SQL Editor'e yapıştırın ve **Run** butonuna tıklayın:

```sql
-- AI Settings tablosuna yeni sağlayıcı kolonları ekle
ALTER TABLE public.ai_settings
ADD COLUMN IF NOT EXISTS gemini_api_key TEXT,
ADD COLUMN IF NOT EXISTS groq_api_key TEXT,
ADD COLUMN IF NOT EXISTS openrouter_api_key TEXT,
ADD COLUMN IF NOT EXISTS openai_api_key TEXT,
ADD COLUMN IF NOT EXISTS gemini_key_set BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS groq_key_set BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS openrouter_key_set BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS openai_key_set BOOLEAN NOT NULL DEFAULT false;

-- Mevcut kolonları güncelle (yeni sağlayıcı modelleri için)
ALTER TABLE public.ai_settings
ADD COLUMN IF NOT EXISTS groq_text_model TEXT DEFAULT 'llama-3.3-70b-versatile',
ADD COLUMN IF NOT EXISTS groq_vision_model TEXT DEFAULT 'llama-3.2-90b-vision-preview',
ADD COLUMN IF NOT EXISTS openrouter_text_model TEXT DEFAULT 'google/gemini-2.0-flash-exp:free',
ADD COLUMN IF NOT EXISTS openrouter_vision_model TEXT DEFAULT 'google/gemini-2.0-flash-exp:free',
ADD COLUMN IF NOT EXISTS openrouter_image_model TEXT DEFAULT 'stable-diffusion-xl',
ADD COLUMN IF NOT EXISTS openai_text_model TEXT DEFAULT 'gpt-4o-mini',
ADD COLUMN IF NOT EXISTS openai_vision_model TEXT DEFAULT 'gpt-4o-mini',
ADD COLUMN IF NOT EXISTS openai_image_model TEXT DEFAULT 'dall-e-3';

-- AI sohbet tabloları için RLS politikaları
ALTER TABLE public.ai_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_messages ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar kendi sohbetlerini görebilir
CREATE POLICY "Users can view own conversations"
ON public.ai_conversations
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own conversations"
ON public.ai_conversations
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own conversations"
ON public.ai_conversations
FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own conversations"
ON public.ai_conversations
FOR DELETE
USING (auth.uid() = user_id);

-- Kullanıcılar kendi mesajlarını görebilir
CREATE POLICY "Users can view own messages"
ON public.ai_messages
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.ai_conversations
    WHERE id = conversation_id AND user_id = auth.uid()
  )
);

CREATE POLICY "Users can insert own messages"
ON public.ai_messages
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.ai_conversations
    WHERE id = conversation_id AND user_id = auth.uid()
  )
);

-- AI Settings için admin erişimi
CREATE POLICY "Admins can manage AI settings"
ON public.ai_settings
FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
);
```

---

## 2. Supabase Edge Function Deploy

### 2.1 Docker ile Deploy (Önerilen)

Docker kurulu ise:

```bash
cd c:/Users/lenovo/cizreapp
supabase functions deploy ai-chat-proxy --no-verify-jwt
```

### 2.2 Supabase Dashboard ile Deploy

Docker yoksa:

1. [Supabase Dashboard](https://supabase.com/dashboard) → Projeniz
2. **Edge Functions** sekmesine gidin
3. **Deploy Edge Function** butonuna tıklayın
4. **ai-chat-proxy** klasörünü seçin (veya zip olarak yükleyin)
5. **Deploy** butonuna tıklayın

---

## 3. AI API Anahtarlarını Girme

### 3.1 Admin Panel Üzerinden

1. Uygulamayı build edin ve çalıştırın
2. Admin hesabıyla giriş yapın
3. **Admin Panel** → **AI Yönetimi** sekmesine gidin
4. **API Anahtarları** tab'ına tıklayın
5. Kullanmak istediğiniz sağlayıcıların API anahtarlarını girin:
   - **Gemini** (Önerilen - ücretsiz tier var)
   - **Groq** (Hızlı, ucuz)
   - **OpenRouter** (Alternatif)
   - **OpenAI** (Son çare - pahalı)

6. Her anahtar için **Kaydet** butonuna tıklayın

### 3.2 API Anahtarı Almak

**Google Gemini:**
1. [Google AI Studio](https://aistudio.google.com/app/apikey) adresine gidin
2. API Key oluşturun
3. Kopyalayın

**Groq:**
1. [console.groq.com](https://console.groq.com) adresine gidin
2. API Keys bölümünden oluşturun
3. Kopyalayın

**OpenRouter:**
1. [openrouter.ai/keys](https://openrouter.ai/keys) adresine gidin
2. API Key oluşturun
3. Kopyalayın

**OpenAI:**
1. [platform.openai.com/api-keys](https://platform.openai.com/api-keys) adresine gidin
2. API Key oluşturun
3. Kopyalayın

---

## 4. Flutter Uygulamasını Güncelleme

### 4.1 pubspec.yaml Kontrolü

AI chat için gerekli paketler:

```yaml
dependencies:
  supabase_flutter: ^2.3.0
  image_picker: ^1.0.7
  cached_network_image: ^3.3.1
  shimmer: ^3.0.0
```

### 4.2 Environment Değişkenleri

`.env` dosyasında Supabase URL ve anon key olduğundan emin olun:

```
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
```

---

## 5. Test Etme

### 5.1 Edge Function Testi

Supabase Dashboard'da Edge Functions sekmesinde:
1. **ai-chat-proxy** function'ını bulun
2. **Test** butonuna tıklayın
3. Test payload'ını girin:

```json
{
  "message": "Merhaba, test mesajı",
  "action": "text"
}
```

### 5.2 Flutter Uygulamasında Test

1. Uygulamayı debug modda çalıştırın
2. AI Chat butonuna (FAB) tıklayın
3. Bir mesaj gönderin
4. Yanıt bekleyin

---

## 6. Akıllı Routing Sistemi

Edge Function şu şekilde çalışır:

| İşlem | Routing Sırası |
|-------|----------------|
| **Text** | Gemini → Groq → OpenRouter → OpenAI |
| **Vision** | Gemini → OpenRouter → OpenAI |
| **Image** | Gemini → OpenRouter → OpenAI |

Her sağlayıcı başarısız olursa otomatik olarak bir sonrakine geçer.

---

## 7. Troubleshooting

### "Function not found" Hatası
- Edge Function'ın deploy edildiğinden emin olun
- Supabase Dashboard'da Edge Functions sekmesini kontrol edin

### "API key yok" Hatası  
- Admin panelden API anahtarlarını girdiğinizden emin olun
- SQL migration'ının çalıştırıldığını doğrulayın

### "permission denied" Hatası
- RLS politikalarını kontrol edin
- Kullanıcının authenticated olduğundan emin olun

### Slow Response / Timeout
- İnternet bağlantısını kontrol edin
- API sağlayıcılarının durumunu kontrol edin
- Model'lerin doğru olduğundan emin olun

---

## 8. Güvenlik Notları

1. **API Anahtarları**: Veritabanında saklanır, asla client-side'da görünmez
2. **RLS Policies**: Kullanıcılar sadece kendi verilerine erişebilir
3. **Service Role Key**: Sadece Edge Function'da kullanılır, client-side'da asla
4. **Rate Limiting**: Gelecekte kullanıcı başına rate limit eklenebilir

---

## 9. Dosya Yapısı

```
supabase/
├── functions/
│   └── ai-chat-proxy/
│       ├── index.ts          # Ana Edge Function kodu
│       └── deno.json         # Deno konfigürasyonu
└── migrations/
    └── add_api_keys_to_settings.sql  # Veritabanı şeması

lib/
├── core/
│   └── models/
│       ├── ai_settings_model.dart    # AI ayarları modeli
│       └── ai_conversation_model.dart # Sohbet modeli
└── features/
    └── ai_chat/
        ├── screens/
        │   ├── ai_chat_list_screen.dart   # Sohbet listesi
        │   └── ai_chat_detail_screen.dart  # Sohbet detayı
        ├── widgets/
        │   └── animated_ai_fab.dart        # Animasyonlu FAB
        └── services/
            └── ai_chat_service.dart        # API servisi
```

---

## 10. Destek

Sorun yaşarsanız:
1. Supabase Dashboard'da Edge Function loglarını kontrol edin
2. Flutter debug konsolunda hataları inceleyin
3. API sağlayıcılarının (Gemini, Groq, vs.) status sayfalarını kontrol edin
