# Push Notification Deploy Komutları

## 🚀 Hızlı Kurulum

Aşağıdaki komutları **cmd** veya **PowerShell**'de sırayla çalıştırın.

---

## 1. Supabase CLI Kurulumu

```bash
scoop install supabase
```

Eğer Scoop yoksa: https://scoop.sh/

---

## 2. Supabase'e Giriş

```bash
supabase login
```

Tarayıcı açılacak, Supabase hesabınızla giriş yapın.

---

## 3. Projeyi Bağla

```bash
cd C:\Users\lenovo\cizreapp
supabase link --project-ref xsbukxkgtmdyickknqzf
```

---

## 4. Firebase Service Account Secret Ekle

**Tek satır JSON (önceden hazırladım):**

```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="{\"type\":\"service_account\",\"project_id\":\"cizreapp-3b9a4\",\"private_key_id\":\"91dd7f2618d7a369f99a4683f4ed99036b41609f\",\"private_key\":\"-----BEGIN PRIVATE KEY-----\\nMIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCjz7RyAShGRH5y\\nbKILBpqYxV6/MBA9CWML+lb3BwxA1RIHDYhByoHz4h3rgKfAxVlkir2NJoquEs3/\\nWMXjnUdadcO/xhJembazAK91plKoFkH57v/tUxkt/fmu3ZO3p/rGhVsnd+oel7NO\\nl0yTKg6pRmlydnRNEPqvLlf4QSDFlBk8UUId0ZPSB8gD2AvYNnreZQM1uBaINyqZ\\nb6uk0CNl2BUa+EyUfoTBVO6N4VFluv+c9846EIhffLR+WpKSlWEg6z1i8n0B5QO5\\n6xHP/m/aGkRjsyeXu1UEnU/2g5mt+L1ymyPQ2KMM1piTV7Un/vWFqnqD46uomCHJ\\n0uwPzWhtAgMBAAECggEAFAR3J/FFQyTukLv+pztE3ANOWy2b5mGFxXpvcxtc33VK\\nESuRqXx+GdfZUSR1G2TiUht0I1IA41mv65KlB/X5uK+oXoBtUTsWbNRaHJXZBupF\\nYK3Yf19GteyRvNEd0nUH+4djRrTsGpXuFt39QQSEKyJME20vNBWtlIekv1TyFMKc\\ndLnR+loIy8AZYHrkwGwTgM5EKM7yYjVyjPaYSCGoxdfwHS96+Btyn7EtFYd+be7e\\nxfaaFipFRC3hJe985TII+Fj5C264JTho5b++gezFn0SoB1hA+SxHYM3yYgxV60C/\\neK2HXUPGawkdSzpuSRwg1kz4Y6peAGyC4RiOTrwxDwKBgQDhhBjpshDEUrKGu5TN\\n3HeCMnSTCtAT8p8e/waAJmfgfToerVXSrV7RG5Stq7hbfkzbeEfg5bT9gyI41Kf8\\nHFwjBQb0y5aEUZtUWuv/uJpNaifeVyoz5GqfhJn9r1Ed2WowiNhJGyAPrDabVcOQ\\nfyjS6G9dCcjeZSE6ZTEKr3RXHwKBgQC59Fbh5r36ESpaPsat1qOQGTj0R+VmEtu1\\niZePjmRlgwWxmffyy6rsJJk+/aoOhSxM7/J+p5Ha23xXMg90WSMBQ+5XH3I7uSwx\\nTtVAOpvZja6vYQc1Jztm6KzlLZ4M69rQcZnPADq4NVeHFUc/mwem/OEkAnrGRQfH\\nvkh9jZiK8wKBgFqcFNZw8UOwZoK0A8ni9zGczDH4ejpJlZ2Coj4DMGGGbz+8LWuE\\ntUAXcNmG0YARcxgLb/Xw1ZO2iJ2E9CnbyzlW38CjvEpV768pCQGqTnUkXfh71T0c\\nXarSQH0pX9I6dOwjT6Ov/mXNr/Mhtn3sWZ7EPVqIf+i7gWpRFi9Q59HJAoGANAGz\\nHuDitwJ//tdZx5qlChMTy7Yj4UVa70249qxTRdS8DezK3Lu7ZOnjdiuJmSADwMzG\\n3EdPUo9aGiTlD5wyXxM5oGIqF6v1QSEUIS+DEPhAJ8qSMnpzcZeXa00zy9dWzj9H\\nTg55XbWFckEwOQjJvhkxelm7LqJ1x5ZfPcYRKKMCgYAWyhx50/D/p7jeHPtP/EBV\\njAQhiacGmsVus3nWdDj2qtz11fn6ViI5qMMwnG1owBQQX4LEIcwtO6z6tNvD2acG\\nxpKuo3xcPzLCY5hisaBxQXkH0AzDLRU7yafcfwUKeSRayAA+efYslmMO2hI/3eZV\\nrG9CoBHSTzRl2DDUmbecDA==\\n-----END PRIVATE KEY-----\\n\",\"client_email\":\"cizreapp@cizreapp-3b9a4.iam.gserviceaccount.com\",\"client_id\":\"113234792116594377652\",\"auth_uri\":\"https://accounts.google.com/o/oauth2/auth\",\"token_uri\":\"https://oauth2.googleapis.com/token\",\"auth_provider_x509_cert_url\":\"https://www.googleapis.com/oauth2/v1/certs\",\"client_x509_cert_url\":\"https://www.googleapis.com/robot/v1/metadata/x509/cizreapp%40cizreapp-3b9a4.iam.gserviceaccount.com\",\"universe_domain\":\"googleapis.com\"}"
```

**NOT:** Komut çok uzun görünüyor ama normal, tamamını kopyala-yapıştır yap.

---

## 5. Edge Function Deploy

```bash
supabase functions deploy send-push-notification
```

Başarılı olursa şöyle bir çıktı göreceksiniz:
```
Deploying function send-push-notification (project ref: xsbukxkgtmdyickknqzf)
Function URL: https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification
Deployed!
```

---

## 6. Database Trigger Çalıştır

1. Supabase Dashboard aç: https://supabase.com/dashboard/project/xsbukxkgtmdyickknqzf
2. Sol menüden **SQL Editor** seç
3. Aşağıdaki SQL'i çalıştır:

```sql
-- Bildirim gönderme fonksiyonu
CREATE OR REPLACE FUNCTION send_notification()
RETURNS TRIGGER AS $$
DECLARE
  fcm_token TEXT;
  function_url TEXT;
  anon_key TEXT;
  notification_data JSONB;
BEGIN
  -- FCM token'ı al
  SELECT fcm_token INTO fcm_token
  FROM profiles
  WHERE id = NEW.user_id;

  -- Token yoksa çık
  IF fcm_token IS NULL THEN
    RETURN NEW;
  END IF;

  -- Edge Function URL ve anon key
  function_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';
  anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnvreHhndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzQ1MzQyODksImV4cCI6MjA1MDExMDI4OX0.mL8pxuD0Nwfsd8d0VKTO8I2hgx8Dkwp4yCMSaD2MwTg';

  -- Notification data hazırla
  notification_data := jsonb_build_object(
    'fcm_token', fcm_token,
    'title', NEW.title,
    'body', NEW.content,
    'data', jsonb_build_object(
      'notification_id', NEW.id,
      'type', NEW.type,
      'entity_id', NEW.entity_id
    )
  );

  -- HTTP isteği gönder (asenkron)
  PERFORM net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || anon_key
    ),
    body := notification_data
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger'ı oluştur
DROP TRIGGER IF EXISTS on_notification_created ON notifications;
CREATE TRIGGER on_notification_created
  AFTER INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION send_notification();

-- Test için bir log yazalım
DO $$
BEGIN
  RAISE NOTICE '✅ Push notification trigger başarıyla kuruldu!';
END $$;
```

---

## 7. Firebase Console'da API Aktifleştir

1. Firebase Console: https://console.firebase.google.com/project/cizreapp-3b9a4
2. Project Settings (⚙️) → **Cloud Messaging** sekmesi
3. **Cloud Messaging API (V1)** bölümünde **Enable** butonuna tıkla

---

## 8. Test Et

Supabase Dashboard → SQL Editor'da test bildirimi gönder:

```sql
-- Önce FCM token'ı olan bir kullanıcı ID'si bul
SELECT id, username, fcm_token FROM profiles WHERE fcm_token IS NOT NULL LIMIT 1;

-- Sonra o kullanıcıya test bildirimi gönder
INSERT INTO notifications (
  user_id,
  type,
  title,
  content,
  actor_id,
  entity_id
) VALUES (
  'YUKARI_GELEN_USER_ID', -- Buraya yukarıdaki sorgudan gelen user ID'yi yaz
  'post_like',
  'Test Bildirim',
  'Push notification testi',
  'YUKARI_GELEN_USER_ID', -- Aynı user ID
  NULL
);
```

---

## ✅ Başarı Kontrolü

1. **Secret kontrolü:**
   ```bash
   supabase secrets list
   ```
   `FIREBASE_SERVICE_ACCOUNT_JSON` görünmeli.

2. **Deploy kontrolü:**
   ```bash
   supabase functions list
   ```
   `send-push-notification` deployed durumunda olmalı.

3. **Edge Function logs:**
   Supabase Dashboard → Edge Functions → send-push-notification → Logs
   
   Başarılı mesajlar göreceksiniz:
   ```
   📤 Push bildirim gönderiliyor (HTTP v1)
   🔑 OAuth access token alınıyor...
   🚀 FCM HTTP v1 isteği gönderiliyor...
   ✅ Push notification gönderildi
   ```

4. **Telefon testi:**
   - Uygulamayı aç
   - Başka bir hesaptan kendini takip et veya gönderini beğen
   - Bildirim gelecek!

---

## 🎯 Tamamlandı!

Artık uygulama içinde yapılan tüm eylemler (beğeni, yorum, takip vb.) otomatik olarak push notification gönderecek! 🎉
