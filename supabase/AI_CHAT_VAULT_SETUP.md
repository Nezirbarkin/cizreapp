# AI Chat — Supabase Vault / Secrets Kurulumu

AI chat özelliği, sağlayıcı API anahtarlarını istemciye ifşa etmeden Supabase Vault'ta güvenli şekilde tutar. Edge Function `ai-chat-proxy` bu anahtarları `Deno.env.get()` ile okur.

## 1. Gemini API Anahtarı

1. https://aistudio.google.com/app/apikey adresine gidin
2. "Create API Key" ile yeni anahtar oluşturun
3. Aşağıdaki komutu çalıştırın:

```bash
supabase secrets set GEMINI_API_KEY=AIzaSy...sizin-anahtarınız...
```

veya Supabase Dashboard → Edge Functions → Secrets üzerinden ekleyin.

## 2. OpenAI API Anahtarı

1. https://platform.openai.com/api-keys adresine gidin
2. "Create new secret key" ile anahtar oluşturun
3. Aşağıdaki komutu çalıştırın:

```bash
supabase secrets set OPENAI_API_KEY=sk-proj-...sizin-anahtarınız...
```

## 3. Edge Function Deploy

```bash
# Function'ı deploy et
supabase functions deploy ai-chat-proxy --no-verify-jwt

# (Eğer JWT doğrulama istenirse --no-verify-jwt kaldırılır; bu durumda
# function auth.uid() bilgisini Supabase client header'ından alır.)
```

> Bu projedeki mevcut edge function'lar `--no-verify-jwt` ile deploy edilir ve `Authorization` header'ından kullanıcıyı doğrular. Aynı yöntem takip edilir.

## 4. Anahtarların Doğruluğunu Test Etme

Admin panelinde "Yapay Zeka Yönetimi" → ilgili sağlayıcı kartı → "Bağlantıyı Test Et" butonuyla test edebilirsiniz.

## 5. Güvenlik Notları

- Anahtarlar asla Flutter istemcisine gönderilmez.
- Edge Function `Deno.env.get('GEMINI_API_KEY')` ile okur.
- Supabase Vault anahtarları `pgsodium` ile şifrelenir.
- Anahtarlar admin UI'dan değiştirilemez; sadece Supabase CLI / Dashboard üzerinden.
- Admin UI, anahtarın set edilip edilmediğini gösterir (var/yok), değeri göstermez.

## 6. Fiyat/Maliyet Takibi (Opsiyonel)

Admin panelinde token kullanımı gösterilir. Tahmini maliyet hesaplamak için (örnek, 2026 fiyatları değişebilir):

- Gemini 1.5 Flash: ~$0.075 / 1M input token, ~$0.30 / 1M output token
- GPT-4o-mini: ~$0.15 / 1M input, ~$0.60 / 1M output
- DALL-E 3 (standart): ~$0.040 / görsel
- Imagen 3: ~$0.04 / görsel

Gerçek fiyatlar için sağlayıcı dokümanlarını kontrol edin.