# Supabase Edge Function ile Push Notification Backend Kurulumu

## 1. Firebase Server Key Al

1. Firebase Console'a git: https://console.firebase.google.com/
2. Projen: **cizreapp-3b9a4**
3. **Project Settings → Cloud Messaging** sekmesine git
4. **"Cloud Messaging API (Legacy)" enabled değilse, enable et**
5. **Server Key**'i kopyala (uzun bir string)

---

## 2. Supabase CLI Yükle

### Windows:
```powershell
# Scoop ile (önerilen)
scoop install supabase

# Veya chocolatey ile
choco install supabase
```

### Mac/Linux:
```bash
brew install supabase/tap/supabase
```

### Manuel kurulum:
https://supabase.com/docs/guides/cli/getting-started

---

## 3. Supabase Projeni Linkle

```bash
# Terminalda proje klasöründe
cd c:/Users/lenovo/cizreapp

# Supabase login
supabase login

# Projeyi linkle
supabase link --project-ref YOUR_PROJECT_REF
# Project ref: Supabase dashboard URL'den al
# Örnek: https://app.supabase.com/project/abcdefghij
# abcdefghij kısmı project ref
```

---

## 4. Edge Function Oluştur

```bash
supabase functions new send-push-notification
```

Bu komut `supabase/functions/send-push-notification/index.ts` dosyasını oluşturur.

---

## 5. Edge Function Kodunu Yaz

`supabase/functions/send-push-notification/index.ts` dosyasını şu kodla değiştir:

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const FIREBASE_SERVER_KEY = Deno.env.get('FIREBASE_SERVER_KEY')!

serve(async (req) => {
  try {
    const { fcm_token, title, body, data } = await req.json()

    if (!fcm_token) {
      return new Response(JSON.stringify({ error: 'FCM token required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Firebase Cloud Messaging API
    const fcmUrl = 'https://fcm.googleapis.com/fcm/send'
    
    const message = {
      to: fcm_token,
      notification: {
        title: title || 'Yeni Bildirim',
        body: body || '',
        sound: 'default',
      },
      data: data || {},
      priority: 'high',
    }

    const response = await fetch(fcmUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `key=${FIREBASE_SERVER_KEY}`,
      },
      body: JSON.stringify(message),
    })

    const result = await response.json()

    if (!response.ok) {
      console.error('FCM Error:', result)
      return new Response(JSON.stringify({ error: 'FCM send failed', details: result }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ success: true, result }), {
      headers: { 'Content-Type': 'application/json' },
    })

  } catch (error) {
    console.error('Error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
```

---

## 6. Firebase Server Key'i Supabase'e Ekle

```bash
supabase secrets set FIREBASE_SERVER_KEY="YOUR_FIREBASE_SERVER_KEY_HERE"
```

---

## 7. Edge Function'ı Deploy Et

```bash
supabase functions deploy send-push-notification
```

---

## 8. Supabase Database Trigger Oluştur

Supabase SQL Editor'da çalıştır:

```sql
-- Edge Function çağırmak için HTTP client extension
CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;

-- Push notification gönderen fonksiyon
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER AS $$
DECLARE
  user_fcm_token TEXT;
  function_url TEXT;
  anon_key TEXT;
BEGIN
  -- Kullanıcının FCM token'ını al
  SELECT fcm_token INTO user_fcm_token
  FROM profiles
  WHERE id = NEW.user_id;
  
  -- FCM token yoksa çık
  IF user_fcm_token IS NULL OR user_fcm_token = '' THEN
    RETURN NEW;
  END IF;
  
  -- Supabase function URL (kendi project URL'inle değiştir)
  function_url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push-notification';
  
  -- Supabase anon key (kendi anon key'inle değiştir)
  anon_key := 'YOUR_ANON_KEY';
  
  -- Edge Function'ı çağır (async)
  PERFORM extensions.http((
    'POST',
    function_url,
    ARRAY[
      extensions.http_header('Content-Type', 'application/json'),
      extensions.http_header('Authorization', 'Bearer ' || anon_key)
    ],
    'application/json',
    json_build_object(
      'fcm_token', user_fcm_token,
      'title', NEW.title,
      'body', NEW.content,
      'data', json_build_object(
        'notification_id', NEW.id,
        'type', NEW.type
      )
    )::text
  )::extensions.http_request);
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger oluştur
DROP TRIGGER IF EXISTS notifications_push_trigger ON notifications;
CREATE TRIGGER notifications_push_trigger
AFTER INSERT ON notifications
FOR EACH ROW
EXECUTE FUNCTION send_push_on_notification();
```

**ÖNEMLİ:** 
- `YOUR_PROJECT_REF` → Supabase project ref'inle değiştir
- `YOUR_ANON_KEY` → Supabase anon key'inle değiştir

---

## 9. Test Et

1. **Başka hesapla giriş yap**
2. **Bir gönderiye beğeni/yorum yap**
3. **İlk hesapta cihaza bildirim gelmeli!**

---

## Sorun Giderme

### Edge Function Loglarını Görüntüle:
```bash
supabase functions logs send-push-notification
```

### Database Trigger Loglarını Kontrol Et:
```sql
SELECT * FROM pg_stat_activity WHERE query LIKE '%send_push%';
```

### FCM Token Kontrol Et:
```sql
SELECT id, username, fcm_token FROM profiles LIMIT 10;
```

---

## Özet Checklist

- [ ] Firebase Server Key alındı
- [ ] Supabase CLI yüklendi
- [ ] Proje linklendi
- [ ] Edge Function oluşturuldu
- [ ] Firebase Server Key secret olarak eklendi
- [ ] Edge Function deploy edildi
- [ ] Database trigger oluşturuldu
- [ ] Test edildi

---

**UYARI:** Bu işlemler oldukça teknik. Hata alırsan loglara bak ve bana bildir!
