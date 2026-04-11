# Firebase Web Entegrasyon Kılavuzu

Bu dokümanda CizreApp web uygulamasına eklenen Firebase Analytics ve Firebase Cloud Messaging (Web Push Bildirimleri) entegrasyonu hakkında bilgiler bulunmaktadır.

## 🎯 Eklenen Özellikler

### 1. Firebase Analytics
- Kullanıcı davranışlarını izleme
- Sayfa görüntülemeleri
- Özel etkinlikler
- Dönüşüm takibi

### 2. Firebase Cloud Messaging (FCM)
- Web push bildirimleri
- Foreground (uygulama açıkken) bildirimler
- Background (arka planda) bildirimler
- Bildirim tıklama yönlendirmeleri

## 📁 Değiştirilen Dosyalar

### 1. `web/index.html`
- Firebase SDK'ları eklendi (Analytics + Messaging)
- Firebase config yapılandırıldı
- FCM token yönetimi eklendi
- Foreground bildirim handler'ı eklendi

**Önemli:** `YOUR_VAPID_KEY_HERE` değerini Firebase Console'dan alınan VAPID key ile değiştirin.

### 2. `web/firebase-messaging-sw.js` (YENİ)
- Background push bildirimleri için service worker
- Firebase Messaging SDK ile entegre
- Bildirim tıklama yönlendirmeleri
- Bildirim türlerine göre routing

### 3. `web/service-worker.js`
- Firebase messaging service worker'ı import eder
- Cache versiyonu v4'e güncellendi

## 🔧 Kurulum Adımları

### 1. VAPID Key Alma (ÖNEMLİ!)

Firebase Console'da şu adımları izleyin:

1. [Firebase Console](https://console.firebase.google.com) açın
2. CizreApp projenizi seçin
3. Sol menüden **Project Settings** (Proje Ayarları) tıklayın
4. **Cloud Messaging** sekmesine gidin
5. **Web configuration** altında **Generate key pair** butonuna tıklayın
6. Oluşturulan **VAPID Key**'i kopyalayın

### 2. VAPID Key'i Ekleyin

`web/index.html` dosyasında şu satırı bulun:

```javascript
vapidKey: "YOUR_VAPID_KEY_HERE" // Firebase Console'dan VAPID key eklenmeli
```

Kopyaladığınız VAPID key ile değiştirin:

```javascript
vapidKey: "BA2xS8y..." // Gerçek VAPID key'iniz
```

### 3. Web Build

```bash
flutter build web --release --base-href /
```

### 4. Test

Localhost'ta test etmek için:

```bash
cd build/web
python -m http.server 8080
```

Tarayıcıda `http://localhost:8080` adresini açın.

## 🧪 Test Senaryoları

### Analytics Testi

1. Web uygulamasını açın
2. Tarayıcı Console'da şu log'u görmelisiniz:
   ```
   [App] Firebase Analytics başlatıldı
   ```

3. Firebase Console > Analytics > Events kısmından gerçek zamanlı olayları izleyin

### Push Notification Testi

#### A. Bildirim İzni İsteme

1. Web uygulamasını açın
2. Console'da şu log'u göreceksiniz:
   ```
   [App] Bildirim izni için kullanıcı etkileşimi bekleniyor
   ```

3. Kullanıcı bir etkileşimde bulunduğunda (örn: butona tıklama) izin istenir

#### B. FCM Token Alma

İzin verildikten sonra:

```
[App] Bildirim izni verildi
[App] FCM Token: dA7s8x9... (token burada görünür)
```

Token localStorage'a `fcmToken` anahtarı ile kaydedilir.

#### C. Test Bildirimi Gönderme

Firebase Console üzerinden:

1. **Cloud Messaging** > **Send test message**
2. FCM token'ı yapıştırın
3. **Test** butonuna tıklayın

**Sonuç:**
- Uygulama açıkken → Foreground bildirim alınır
- Uygulama arka plandayken → Background bildirim gelir
- Bildirime tıklandığında → Uygulama açılır ve ilgili sayfaya yönlendirilir

## 🔔 Bildirim Türleri ve Routing

### Desteklenen Bildirim Türleri

`firebase-messaging-sw.js` içinde aşağıdaki bildirim türleri yönlendirme destekler:

| Tür | Data Alanı | Yönlendirme |
|-----|------------|-------------|
| `post_like` | `postId` | `/post/{postId}` |
| `comment` | `postId` | `/post/{postId}` |
| `follow` | `userId` | `/profile/{userId}` |
| `order` | `orderId` | `/orders/{orderId}` |
| `message` | `conversationId` | `/messages/{conversationId}` |

### Bildirim Gönderme Formatı

Backend'den (Supabase Edge Function) bildirim gönderirken:

```json
{
  "notification": {
    "title": "Yeni Beğeni",
    "body": "Ahmet gönderinizi beğendi"
  },
  "data": {
    "type": "post_like",
    "postId": "123456"
  },
  "token": "FCM_TOKEN_HERE"
}
```

## 🔐 Güvenlik Notları

1. **VAPID Key:** Public key olup güvenlik sorunu yaratmaz, ancak yine de dikkatli olun
2. **FCM Token:** Her kullanıcıya özel, localStorage'da saklanır
3. **Token Yenileme:** Token'lar periyodik olarak yenilenebilir, `onTokenRefresh` ile yönetilir

## 📊 Firebase Console - Analytics Metrikleri

### Temel Metrikler
- **Active Users:** Aktif kullanıcı sayısı
- **Engagement:** Kullanıcı etkileşimi
- **Screen Views:** Sayfa görüntülemeleri
- **Events:** Özel etkinlikler

### Özel Events
Flutter uygulamasından özel event'ler gönderilebilir:

```dart
import 'package:firebase_analytics/firebase_analytics.dart';

FirebaseAnalytics.instance.logEvent(
  name: 'share_post',
  parameters: {
    'post_id': '123',
    'method': 'twitter',
  },
);
```

## 🚨 Sık Karşılaşılan Sorunlar

### 1. "VAPID key not found" Hatası
**Çözüm:** VAPID key'i `web/index.html` dosyasına ekleyin

### 2. "Service Worker registration failed"
**Çözüm:** HTTPS üzerinde çalıştığınızdan emin olun (localhost hariç)

### 3. "Notification permission denied"
**Çözüm:** 
- Tarayıcı ayarlarından site için bildirim izni verin
- `chrome://settings/content/notifications`

### 4. FCM Token Alınamıyor
**Çözüm:**
- Firebase Console'da Web App eklendiğinden emin olun
- VAPID key'in doğru olduğunu kontrol edin
- Service Worker'ın düzgün yüklendiğini kontrol edin

## 📱 Tarayıcı Desteği

### Desteklenen Tarayıcılar
- ✅ Chrome (Desktop & Mobile)
- ✅ Firefox (Desktop & Mobile)
- ✅ Edge
- ✅ Opera
- ✅ Samsung Internet
- ⚠️ Safari (iOS 16.4+ kısıtlı destek)

### Desteklenmeyen
- ❌ Internet Explorer
- ❌ Safari < iOS 16.4

## 🔄 Token Yönetimi

### Backend'e Token Kaydetme

Flutter uygulaması FCM token'ı otomatik olarak Supabase'e kaydeder:

```dart
// lib/core/services/push_notification_service.dart
await supabase
  .from('profiles')
  .update({'fcm_token': token})
  .eq('id', userId);
```

### Web'den Token Alma

```javascript
// localStorage'dan token oku
const fcmToken = localStorage.getItem('fcmToken');

// veya messaging instance'dan al
const token = await messaging.getToken();
```

## 📚 İleri Seviye

### Custom Service Worker Event'leri

`firebase-messaging-sw.js` dosyasına özel handler'lar ekleyebilirsiniz:

```javascript
// Özel notification action handler
self.addEventListener('notificationclick', (event) => {
  if (event.action === 'view-post') {
    // Özel action işleme
  }
});
```

### Analytics Custom Parameters

```javascript
firebase.analytics().logEvent('custom_event', {
  category: 'engagement',
  action: 'click',
  label: 'button_name'
});
```

## 🎉 Sonuç

Firebase Analytics ve Cloud Messaging entegrasyonu tamamlandı. Artık:

- ✅ Kullanıcı davranışları izlenebilir
- ✅ Web push bildirimleri gönderilebilir
- ✅ Bildirim tıklama yönlendirmeleri çalışır
- ✅ Foreground ve background bildirimler desteklenir

## 📞 Destek

Sorun yaşarsanız:
1. Console log'larını kontrol edin
2. Firebase Console > Cloud Messaging > Send test message ile test edin
3. Tarayıcı izinlerini kontrol edin

---

**Son Güncelleme:** 16 Mart 2026
**Versiyon:** 1.0.0
