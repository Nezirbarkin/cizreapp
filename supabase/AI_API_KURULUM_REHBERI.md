# CizreApp AI - API Kurulum Rehberi

Bu rehber, CizreApp'in yapay zeka sohbet özelliğinin çalışması için gerekli API anahtarlarının nasıl alınacağını ve kurulacağını açıklar.

## 🌐 Akıllı Routing Mekanizması

CizreApp AI, **akıllı fallback mekanizması** kullanır:

| İstek Türü | Sıra | Açıklama |
|---|---|---|
| **Text** | Gemini → Groq → OpenRouter → OpenAI | Hangisi müsaitse ona gider |
| **Vision** (resim analizi) | Gemini → OpenRouter → OpenAI | Resim anlayabilen sağlayıcılara |
| **Image Generation** | Gemini (Imagen) → OpenRouter (Flux/SD) → OpenAI (DALL-E) | Resim üretebilen sağlayıcılara |

---

## 📋 1. Gemini API Anahtarı (ZORUNLU - Birincil Sağlayıcı)

Gemini, ücretsiz katmanıyla en uygun maliyetli seçenektir.

### Adım 1: Google AI Studio'ya gidin
- URL: **https://aistudio.google.com/app/apikey**
- Google hesabınızla giriş yapın

### Adım 2: API Anahtarı Oluşturun
1. **"Create API Key"** butonuna tıklayın
2. **"Create API key in new project"** veya mevcut bir proje seçin
3. Anahtarınız oluşturulur: `AIzaSy...` ile başlar
4. **KOPYALAYIN** — bu anahtarı bir daha göremezsiniz!

### Adım 3: Supabase'e Ekleyin
VS Code terminalinde:
```powershell
supabase secrets set GEMINI_API_KEY=AIzaSy_BURAYA_KENDI_ANAHTARINIZI_YAPISTIRIN
```

### Ücretsiz Limit (2026)
- Dakikada 15 istek
- Günde 1.500 istek
- Ayda 1 milyon token

---

## 🚀 2. Groq API Anahtarı (ÖNERİLİR - Hızlı Fallback)

Groq, LPU donanımıyla çok hızlı çıkarım sağlar. Ücretsiz katmanı geniştir.

### Adım 1: Groq Console'a gidin
- URL: **https://console.groq.com/keys**
- Hesap oluşturun veya giriş yapın

### Adım 2: API Anahtarı Oluşturun
1. **"Create API Key"** butonuna tıklayın
2. Bir isim verin (örn: "cizreapp")
3. Anahtarınız oluşturulur: `gsk_...` ile başlar
4. **KOPYALAYIN**

### Adım 3: Supabase'e Ekleyin
```powershell
supabase secrets set GROQ_API_KEY=gsk_BURAYA_KENDI_ANAHTARINIZI_YAPISTIRIN
```

### Ücretsiz Limit (2026)
- Dakikada 30 istek
- Günde 14.400 istek
- Token limiti: dakikada 6.000

### Desteklenen Modeller
- `llama-3.3-70b-versatile` (text)
- `llama-3.2-90b-vision-preview` (vision)
- ❌ Resim üretimi yok

---

## 🔀 3. OpenRouter API Anahtarı (ÖNERİLİR - Çok Yönlü Yedek)

OpenRouter, birçok modeli tek API ile kullanmanızı sağlar. Ücretsiz modeller mevcuttur.

### Adım 1: OpenRouter'a gidin
- URL: **https://openrouter.ai/keys**
- Hesap oluşturun veya giriş yapın

### Adım 2: API Anahtarı Oluşturun
1. **"Create Key"** butonuna tıklayın
2. Bir isim verin
3. Anahtarınız oluşturulur: `sk-or-...` ile başlar
4. **KOPYALAYIN**

### Adım 3: Supabase'e Ekleyin
```powershell
supabase secrets set OPENROUTER_API_KEY=sk-or-_BURAYA_KENDI_ANAHTARINIZI_YAPISTIRIN
```

### Ücretsiz Modeller
OpenRouter'da ücretsiz modeller (rate limitli):
- `google/gemini-2.0-flash-exp:free` (text + vision)
- `meta-llama/llama-3.3-70b-instruct:free` (text)
- Resim üretimi: `stable-diffusion-xl` (ücretli)

### Ücretli Modeller
- `openai/gpt-4o-mini` (~$0.15/1M token)
- `anthropic/claude-3.5-haiku` (~$0.25/1M token)
- Resim: `flux-1-schnell` (~$0.003/görsel)

---

## 🧠 4. OpenAI API Anahtarı (OPSİYONEL - Son Çare)

OpenAI, en pahalı seçenektir ama en yüksek kaliteyi sunar. Sadece diğer sağlayıcılar başarısız olursa kullanılır.

### Adım 1: OpenAI Platform'a gidin
- URL: **https://platform.openai.com/api-keys**
- Hesap oluşturun (kredi kartı gerekli)

### Adım 2: API Anahtarı Oluşturun
1. **"Create new secret key"** butonuna tıklayın
2. Bir isim verin (örn: "cizreapp")
3. Anahtarınız oluşturulur: `sk-proj-...` ile başlar
4. **KOPYALAYIN** — bir daha gösterilmez!

### Adım 3: Supabase'e Ekleyin
```powershell
supabase secrets set OPENAI_API_KEY=sk-proj-_BURAYA_KENDI_ANAHTARINIZI_YAPISTIRIN
```

### Fiyatlandırma
- GPT-4o-mini: ~$0.15/1M input token
- DALL-E 3: ~$0.04/görsel (1024x1024)

---

## ✅ 5. Doğrulama

Tüm anahtarları ayarladıktan sonra kontrol edin:

```powershell
supabase secrets list
```

Beklenen çıktı:
```
NAME                  DIGEST
GEMINI_API_KEY        a1b2c3d4...
GROQ_API_KEY          e5f6g7h8...
OPENROUTER_API_KEY    i9j0k1l2...
OPENAI_API_KEY        m3n4o5p6...
```

> **NOT**: En az GEMINI_API_KEY ayarlanmış olmalıdır. Diğerleri opsiyonel ama önerilir.

---

## 🚀 6. Edge Function Deploy

Anahtarları ayarladıktan sonra:

```powershell
supabase functions deploy ai-chat-proxy --no-verify-jwt
```

---

## 📊 7. Admin Panel'den Test

1. Uygulamayı açın: `flutter run`
2. Admin olarak giriş yapın
3. Drawer'dan **"Yapay Zeka Yönetimi"** sekmesine gidin
4. **Genel** sekmesinde: Özelliğin açık olduğunu doğrulayın
5. **API Anahtarları** sekmesinde: Anahtarların durumunu kontrol edin
6. **Modeller & Prompt** sekmesinde: Model isimlerini doğrulayın

---

## 💡 Maliyet Optimizasyonu

| Senaryo | Önerilen Ayar |
|---|---|
| **Minimum maliyet** | Sadece Gemini (ücretsiz) |
| **Dengeli** | Gemini + Groq (ikisi de ücretsiz katman) |
| **Tam yedek** | Gemini + Groq + OpenRouter (ücretsiz modeller) |
| **Premium** | Tüm 4 sağlayıcı |

**Akıllı routing** sayesinde, bir sağlayıcı başarısız olursa otomatik olarak bir sonrakine geçer. Kullanıcı hangi sağlayıcının kullanıldığını görmez — hepsi "CizreApp AI" olarak görünür.