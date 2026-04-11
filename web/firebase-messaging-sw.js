// Firebase Cloud Messaging Service Worker
// Bu dosya background (arka plan) push bildirimlerini yönetir

// Firebase SDK'ları import et
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js');

// Firebase yapılandırması
const firebaseConfig = {
  apiKey: "AIzaSyBdAl0dWh-MtbNhBF7nbt_FPPvTpsllI-8",
  authDomain: "cizreapp-3b9a4.firebaseapp.com",
  projectId: "cizreapp-3b9a4",
  storageBucket: "cizreapp-3b9a4.firebasestorage.app",
  messagingSenderId: "224517445508",
  appId: "1:224517445508:web:d906adc167aade41cbafd1",
  measurementId: "G-37K9ZJDLFG"
};

// Firebase'i başlat
firebase.initializeApp(firebaseConfig);

// Messaging instance
const messaging = firebase.messaging();

// Background bildirimlerini yönet
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Background bildirim alındı:', payload);

  const notificationTitle = payload.notification?.title || 'CizreApp';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data,
    tag: payload.data?.type || 'general',
    requireInteraction: false,
    vibrate: [200, 100, 200]
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

// Bildirime tıklandığında
self.addEventListener('notificationclick', (event) => {
  console.log('[firebase-messaging-sw.js] Bildirime tıklandı:', event.notification);
  
  event.notification.close();

  // Uygulamayı aç veya odaklan
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        // Zaten açık bir pencere varsa odaklan
        for (let i = 0; i < clientList.length; i++) {
          const client = clientList[i];
          if (client.url.includes('cizreapp.com') && 'focus' in client) {
            return client.focus();
          }
        }
        
        // Açık pencere yoksa yeni pencere aç
        if (clients.openWindow) {
          const data = event.notification.data;
          let url = '/';
          
          // Bildirim türüne göre yönlendir
          if (data?.type === 'post_like') {
            url = `/post/${data.postId}`;
          } else if (data?.type === 'comment') {
            url = `/post/${data.postId}`;
          } else if (data?.type === 'follow') {
            url = `/profile/${data.userId}`;
          } else if (data?.type === 'order') {
            url = `/orders/${data.orderId}`;
          } else if (data?.type === 'message') {
            url = `/messages/${data.conversationId}`;
          }
          
          return clients.openWindow(url);
        }
      })
  );
});

console.log('[firebase-messaging-sw.js] Service Worker yüklendi');
