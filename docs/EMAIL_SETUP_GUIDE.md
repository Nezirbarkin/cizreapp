# 📧 Supabase Email Edge Function Kurulum Kılavuzu

Bu kılavuz, sipariş teslim edildiğinde müşteriye email gönderme özelliğini aktif etmeniz için adım adım talimatlar içerir.

## 🔑 1. Resend Hesabı Oluşturma

1. **https://resend.com** adresine gidin
2. **"Start building"** veya **"Sign up"** butonuna tıklayın
3. GitHub veya email ile kayıt olun
4. Email doğrulaması yapın
5. Dashboard'a giriş yapın

### API Key Alma
1. Sol menüden **"API Keys"** tıklayın
2. **"Create API Key"** butonuna tıklayın
3. Key'e bir isim verin (örn: "CizreApp")
4. **"Create"** tıklayın
5. Oluşan API Key'i kopyalayın (re_xxxxxx... formatında)
   
   ⚠️ **ÖNEMLİ:** Bu key'i sadece bir kez görebilirsiniz, güvenli bir yere kaydedin!

### Domain Doğrulama (Opsiyonel ama Önerilen)
Ücretsiz planda `onboarding@resend.dev` adresinden gönderilir. Kendi domain'inizi kullanmak için:
1. Sol menüden **"Domains"** tıklayın
2. **"Add Domain"** tıklayın
3. Domain'inizi ekleyin (örn: cizreapp.com)
4. DNS kayıtlarını ekleyin (MX, TXT)
5. Doğrulama tamamlanınca email gönderebilirsiniz

## 🚀 2. Supabase CLI Kurulumu (Windows)

### Adım 2.1: Node.js Kurulumu
Node.js yoksa: https://nodejs.org (LTS sürümünü indirin)

### Adım 2.2: Supabase CLI Kurulumu
PowerShell veya CMD açın:
```bash
npm install -g supabase
```

Kontrol:
```bash
supabase --version
```

## 🔐 3. Supabase Projesine Bağlanma

### Adım 3.1: Login
```bash
supabase login
```
Tarayıcıda açılan sayfada Supabase hesabınızla giriş yapın.

### Adım 3.2: Proje Bağlantısı
Proje klasöründe (cizreapp) çalıştırın:
```bash
supabase link --project-ref PROJE_REF_ID
```

`PROJE_REF_ID`'yi şuradan bulabilirsiniz:
- Supabase Dashboard → Settings → General → Reference ID

## 📤 4. Edge Function Deploy Etme

### Adım 4.1: Function Deploy
```bash
supabase functions deploy send-email
```

Deploy başarılı olduğunda şöyle bir çıktı göreceksiniz:
```
Bundling function: send-email
Uploading bundle to Supabase...
Function send-email deployed!
```

### Adım 4.2: Resend API Key Ekleme
```bash
supabase secrets set RESEND_API_KEY=re_xxxxxxxxxxxxxx
```

`re_xxxxxxxxxxxxxx` yerine Resend'den aldığınız gerçek API key'i yazın.

## ✅ 5. Test Etme

### Web UI'dan Test (Kolay)
1. Supabase Dashboard → Edge Functions → send-email
2. **"Invoke"** butonuna tıklayın
3. Request body'ye şunu yazın:
```json
{
  "type": "order_delivered",
  "to": "sizin@email.com",
  "data": {
    "customerName": "Test Müşteri",
    "orderNumber": "12345",
    "shopName": "Test Dükkan",
    "totalAmount": "150.00",
    "deliveredAt": "2024-02-05T15:00:00Z"
  }
}
```
4. **"Run"** tıklayın
5. Email adresinizi kontrol edin (spam klasörünü de kontrol edin)

### Uygulama Üzerinden Test
1. Uygulamayı açın
2. Bir sipariş oluşturun veya mevcut siparişi kullanın
3. Satıcı panelinden sipariş durumunu **"Teslim Edildi"** yapın
4. Email adresinize bildirim gelecek

## ❓ Sorun Giderme

### "Function not found" Hatası
- Edge function doğru deploy edilmemiş olabilir
- `supabase functions list` ile kontrol edin

### Email Gelmiyor
1. Spam klasörünü kontrol edin
2. Resend dashboard'da Logs'u kontrol edin
3. Supabase Edge Function logs'u kontrol edin:
   - Dashboard → Edge Functions → send-email → Logs

### API Key Hatası
```bash
supabase secrets list
```
RESEND_API_KEY görünüyorsa sorun key'in kendisinde olabilir.

### CORS Hatası
Edge function kodu CORS headers içeriyor, sorun olmamalı.

## 📊 Kullanım Limitleri

### Resend Ücretsiz Plan
- **Günlük:** 100 email
- **Aylık:** 3,000 email
- Tek domain

### Ücretli Planlar
- Pro: $20/ay - 50,000 email
- Enterprise: Sınırsız

## 🔒 Güvenlik Notları

1. API Key'i asla client-side kodda kullanmayın
2. Edge Function her zaman server-side çalışır (güvenli)
3. Environment variable olarak saklayın

## 📁 Dosya Yapısı

```
cizreapp/
├── supabase/
│   └── functions/
│       └── send-email/
│           └── index.ts      ← Edge Function kodu
├── lib/
│   └── core/
│       └── services/
│           └── email_service.dart  ← Flutter servisi
```

---

## 🎉 Kurulum Tamamlandı!

Artık:
- Sipariş teslim edildiğinde → Müşteriye email gider
- Sipariş onaylandığında → Müşteriye email gider (opsiyonel)

Sorularınız için: [GitHub Issues]
