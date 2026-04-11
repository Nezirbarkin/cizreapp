# Firebase Push Notification Setup Rehberi

## 1. Firebase Console'da Proje Oluştur

1. **Firebase Console'a git**: https://console.firebase.google.com/
2. **"Add project" veya "Proje ekle" tıkla**
3. **Proje adını gir**: `CizreApp` (veya istediğin bir ad)
4. **Google Analytics**: İsteğe bağlı (aktif etmeni öneririm)
5. **Projeyi oluştur**

---

## 2. Android App Ekle

### 2.1. Firebase Console'da Android App Ekle
1. Projen açıkken **"Add app" → Android simgesi** tıkla
2. **Android package name**: `com.example.cizreapp`
   - Bunu kontrol etmek için: `android/app/src/main/AndroidManifest.xml` dosyasını aç
   - `<manifest package="com.example.cizreapp">` sat��rını bul
3. **App nickname**: CizreApp (isteğe bağlı)
4. **Debug signing certificate SHA-1**: Şimdilik boş bırakabilirsin
5. **"Register app" tıkla**

### 2.2. google-services.json İndir ve Yerleştir
1. Firebase Console'dan **`google-services.json`** dosyasını indir
2. Bu dosyayı **`android/app/`** klasörüne kopyala
   ```
   android/
     app/
       google-services.json  ← Buraya
   ```

### 2.3. Android Gradle Dosyalarını Güncelle

#### `android/build.gradle` (Proje seviyesi)
```gradle
buildscript {
    dependencies {
        // Firebase plugin ekle
        classpath 'com.google.gms:google-services:4.4.2'
    }
}
```

#### `android/app/build.gradle` (App seviyesi)
En sona ekle:
```gradle
apply plugin: 'com.google.gms.google-services'
```

### 2.4. AndroidManifest.xml Güncelle
`android/app/src/main/AndroidManifest.xml` dosyasına ekle:

```xml
<manifest>
    <application>
        <!-- Mevcut kodlar... -->
        
        <!-- Firebase Messaging -->
        <service
            android:name="io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService"
            android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT" />
            </intent-filter>
        </service>
        
        <!-- Varsayılan notification channel -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="high_importance_channel" />
    </application>
    
    <!-- İzinler -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
</manifest>
```

---

## 3. iOS App Ekle (İsteğe Bağlı)

### 3.1. Firebase Console'da iOS App Ekle
1. **"Add app" → iOS simgesi** tıkla
2. **iOS bundle ID**: `ios/Runner.xcodeproj` dosyasını aç, Bundle Identifier'ı bul
3. **App nickname**: CizreApp
4. **"Register app" tıkla**

### 3.2. GoogleService-Info.plist İndir
1. **`GoogleService-Info.plist`** dosyasını indir
2. Xcode'da `ios/Runner/` klasörüne sürükle-bırak
3. "Copy items if needed" seçeneğini işaretle

### 3.3. iOS Capabilities Ekle
1. Xcode'da projeyi aç: `ios/Runner.xcworkspace`
2. **Signing & Capabilities** sekmesine git
3. **"+ Capability" tıkla**
4. **"Push Notifications"** ekle
5. **"Background Modes"** ekle ve **"Remote notifications"** işaretle

---

## 4. firebase_options.dart Güncelle

Firebase Console'dan değerleri al:
1. **Project Settings → General** sekmesine git
2. **Your apps** bölümünden Android ve iOS için değerleri kopyala

`lib/firebase_options.dart` dosyasını güncelle:

```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'AIzaSy...', // Firebase Console'dan kopyala
  appId: '1:123456789:android:abc123', // Firebase Console'dan kopyala
  messagingSenderId: '123456789', // Firebase Console'dan kopyala
  projectId: 'cizreapp-12345', // Firebase Console'dan kopyala
  storageBucket: 'cizreapp-12345.appspot.com', // Firebase Console'dan kopyala
);
```

---

## 5. Supabase Veritabanına fcm_token Alanı Ekle

Supabase SQL Editor'da çalıştır:

```sql
-- profiles tablosuna fcm_token sütunu ekle
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- Index ekle (performans için)
CREATE INDEX IF NOT EXISTS profiles_fcm_token_idx ON public.profiles(fcm_token);
```

---

## 6. Flutter Paketlerini Yükle

Terminal'de çalıştır:
```bash
flutter pub get
```

---

## 7. Test Et

### 7.1. Uygulamayı Çalıştır
```bash
flutter run
```

### 7.2. Konsol Loglarını Kontrol Et
Aşağıdaki logları görmelisin:
```
🔥 Firebase Messaging initialize ediliyor...
✅ Bildirim izni verildi
🔑 FCM Token: ey...
✅ FCM token Supabase'e kaydedildi
✅ Firebase Messaging initialize edildi
```

### 7.3. Firebase Console'dan Test Bildirimi Gönder
1. Firebase Console → **Cloud Messaging**
2. **"Send your first message"** tıkla
3. Notification başlığı ve metni yaz
4. **"Send test message"** tıkla
5. FCM token'ı yapıştır (konsoldan kopyala)
6. **"Test"** tıkla

---

## 8. Supabase Edge Function ile Push Gönderme (Gelişmiş)

Bildirim oluşturulduğunda otomatik push göndermek için Supabase Edge Function gerekir.

### 8.1. Firebase Service Account Key Al
1. Firebase Console → **Project Settings → Service Accounts**
2. **"Generate new private key"** tıkla
3. JSON dosyasını indir (GÜVENLİ SAK LA!)

### 8.2. Supabase Edge Function Oluştur

```typescript
// supabase/functions/send-push-notification/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  const { fcm_token, title, body, data } = await req.json()
  
  const firebaseUrl = `https://fcm.googleapis.com/v1/projects/YOUR_PROJECT_ID/messages:send`
  
  const message = {
    message: {
      token: fcm_token,
      notification: {
        title: title,
        body: body,
      },
      data: data || {},
    }
  }
  
  const response = await fetch(firebaseUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${Deno.env.get('FIREBASE_ACCESS_TOKEN')}`,
    },
    body: JSON.stringify(message),
  })
  
  return new Response(JSON.stringify({ success: true }), {
    headers: { 'Content-Type': 'application/json' },
  })
})
```

### 8.3. Supabase Trigger Ekle

```sql
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER AS $$
DECLARE
  user_fcm_token TEXT;
BEGIN
  -- Kullanıcının FCM token'ını al
  SELECT fcm_token INTO user_fcm_token
  FROM profiles
  WHERE id = NEW.user_id;
  
  -- FCM token varsa push gönder
  IF user_fcm_token IS NOT NULL THEN
    PERFORM
      net.http_post(
        url := 'YOUR_SUPABASE_URL/functions/v1/send-push-notification',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer YOUR_ANON_KEY'
        ),
        body := jsonb_build_object(
          'fcm_token', user_fcm_token,
          'title', NEW.title,
          'body', NEW.content
        )
      );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger oluştur
CREATE TRIGGER notifications_push_trigger
AFTER INSERT ON notifications
FOR EACH ROW
EXECUTE FUNCTION send_push_on_notification();
```

---

## Sorun Giderme

### Android'de bildirim gelmiyor
1. `google-services.json` doğru yerde mi kontrol et
2. `flutter clean && flutter pub get` çalıştır
3. Uygulamayı yeniden yükle

### iOS'ta bildirim gelmiyor
1. Push Notifications capability eklendi mi kontrol et
2. Apple Developer Console'da Push Notification sertifikası oluştur
3. Fiziksel cihazda test et (simulator'da çalışmaz)

### FCM Token null geliyor
1. İzin verildi mi kontrol et
2. Internet bağlantısı var mı kontrol et
3. Firebase initialize oldu mu kontrol et

---

## Özet Checklist

- [ ] Firebase projesi oluşturuldu
- [ ] Android app eklendi
- [ ] google-services.json yerleştirildi
- [ ] Android Gradle dosyaları güncellendi
- [ ] AndroidManifest.xml güncellendi
- [ ] firebase_options.dart güncellendi
- [ ] Supabase'e fcm_token sütunu eklendi
- [ ] flutter pub get çalıştırıldı
- [ ] Uygulama test edildi
- [ ] Firebase Console'dan test bildirimi gönderildi

---

**ÖNEMLI NOT**: Push notification sistemi oldukça karmaşık. İlk kurulumda sorun yaşarsan normal. Adım adım git ve logları dikkatle takip et!
