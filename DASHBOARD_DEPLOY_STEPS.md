# 🚀 Supabase Dashboard - Edge Function Deploy Adımları

## 📍 URL: https://supabase.com/dashboard/project/xsbukxkgtmdyickknqzf/functions

---

## Adım 1: Edge Functions Sayfasına Git
1. Yukarıdaki URL'ye tıklayın
2. Veya: Supabase Dashboard → Projeniz → **Edge Functions** (sol menü)

---

## Adım 2: Yeni Function Oluştur
1. **Create Function** butonuna tıklayın (sağ üstte)
2. Function formunu doldurun:
   - **Name:** `send-push`
   - **Verify Method:** `None` (varsayılan bırakın)
3. **Create** butonuna tıklayın

---

## Adım 3: Kodu Yapıştırın
1. `supabase/functions/send-push/index.ts` dosyasını açın
2. Tüm kodu kopyalayın (CTRL+A, CTRL+C)
3. Supabase Dashboard'daki kod editörüne yapıştırın
4. **Save** butonuna tıklayın

---

## Adım 4: Secret Ekle
1. Edge Function sayfasında **Secrets** sekmesine tıklayın
2. **Add Secret** butonuna tıklayın
3. Formu doldurun:
   - **Name:** `FIREBASE_SERVICE_ACCOUNT`
   - **Secret:** `[Daha önce indirdiğiniz Firebase Service Account JSON'ın tamamı]`

   Örnek (bütün JSON'u yapıştırın):
   ```json
   {
     "type": "service_account",
     "project_id": "cizreapp-3b9a4",
     "private_key_id": "...",
     "private_key": "...",
     "client_email": "...",
     "client_id": "...",
     "auth_uri": "https://accounts.google.com/o/oauth2/auth",
     "token_uri": "https://oauth2.googleapis.com/token",
     ...
   }
   ```
4. **Save Secret** butonuna tıklayın

---

## Adım 5: Deploy Edin
1. **Deploy** butonuna tıklayın
2. Function URL görünecek:
   ```
   https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push
   ```
3. Deploy başarılı olursa ✅ yeşil tik göreceksiniz

---

## Adım 6: Test Edin
1. Supabase SQL Editor'u açın
2. Test SQL'i çalıştırın:

```sql
-- Kendi user ID'nizi kullanın
SELECT send_fcm_push_notification(
    'SIZIN_USER_ID',
    'Test Push',
    'Bu bir test bildirimidir'
);
```

3. Flutter uygulamanızı açın
4. Bildirim gelmeli: `📲 Foreground bildirim alındı: Test Push`

---

## 🔍 Debug: Edge Function Logları
1. Supabase Dashboard → Edge Functions → send-push
2. **Logs** sekmesine tıklayın
3. Gelen istekleri ve hataları görebilirsiniz

---

## ✅ Başarı Kontrolü
- [ ] Edge Function oluşturuldu
- [ ] Kod yapıştırıldı
- [ ] FIREBASE_SERVICE_ACCOUNT secret eklendi
- [ ] Deploy başarılı oldu
- [ ] Test SQL'i çalıştırıldı
- [ ] Cihazda push bildirimi alındı
