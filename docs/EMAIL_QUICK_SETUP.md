# 🚀 Hızlı Email Kurulum (API Key Var)

Resend API key'iniz zaten var. Sadece Edge Function deploy edin.

## 📋 Yapılacaklar

### 1. Terminal'de Proje Klasörüne Git
```bash
cd c:\Users\lenovo\cizreapp
```

### 2. Supabase Login (İlk Kez)
```bash
supabase login
```
Tarayıcıda açılan sayfada giriş yapın.

### 3. Proje Bağlantısı (İlk Kez)
```bash
supabase link
```
Listeden projenizi seçin.

### 4. Edge Function Deploy
```bash
supabase functions deploy send-email
```

### 5. API Key Ekle
```bash
supabase secrets set RESEND_API_KEY=re_xxxxxxxxxxxxxx
```
`re_xxxxxxxxxxxxxx` yerine Resend'den aldığınız gerçek key'i yazın.

## ✅ Test

### Terminal'den Test
```bash
supabase functions invoke send-email --body "{\"type\":\"order_delivered\",\"to\":\"sizin@email.com\",\"data\":{\"customerName\":\"Test\",\"orderNumber\":\"123\",\"shopName\":\"Test Dükkan\",\"totalAmount\":\"100\",\"deliveredAt\":\"2024-02-05T15:00:00Z\"}}"
```

Veya Supabase Dashboard → Edge Functions → send-email → Invoke

## 🎉 Tamamlandı!

Artık sipariş "Teslim Edildi" durumuna geçtiğinde müşteriye otomatik email gidecek.

---

**Sorun mu var?** 
- `supabase functions list` ile kontrol edin
- Supabase Dashboard → Edge Functions → Logs'dan hataları görün
