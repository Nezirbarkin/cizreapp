// Optimized service worker for CizreApp
// Küçültülmüş ve hızlı yükleme için tasarlanmış

const CACHE_NAME = 'cizreapp-v5';
const URLS_TO_CACHE = [
  '/',
  '/index.html',
];

// Service Worker kurulum - Hızlı cache'leme
self.addEventListener('install', (event) => {
  console.log('[SW] Installing service worker...');
  self.skipWaiting(); // Hemen aktif et
});

// Service Worker aktivasyon - Eski cache'i sil
self.addEventListener('activate', (event) => {
  console.log('[SW] Activating service worker...');
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME) {
            console.log('[SW] Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  self.clients.claim();
});

// Network-first strategy for faster load
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // API istekleri için - network only, cache yok
  if (request.method === 'POST' || request.method === 'PUT' || request.method === 'DELETE' ||
      url.pathname.startsWith('/api/') || url.pathname.startsWith('/rest/')) {
    event.respondWith(
      fetch(request).catch(() => {
        return new Response('API Error', { status: 503 });
      })
    );
    return;
  }

  // Flutter assets için - cache first
  if (url.pathname.startsWith('/assets/') ||
      url.pathname.startsWith('/canvaskit/') ||
      url.pathname.endsWith('.js') ||
      url.pathname.endsWith('.wasm') ||
      url.pathname.endsWith('.json')) {
    event.respondWith(
      caches.match(request).then((cached) => {
        if (cached) return cached;
        return fetch(request).then((response) => {
          if (response && response.ok) {
            const responseClone = response.clone();
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(request, responseClone);
            }).catch(() => {}); // Cache hatası yoksay
          }
          return response;
        }).catch(() => {
          return new Response('Not found', { status: 404 });
        });
      })
    );
    return;
  }

  // Navigation istekleri için - network önce
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).catch(() => {
        // Network başarısız, cache'ten geri dön
        return caches.match(request).then((cached) => {
          return cached || new Response('Offline - No connection', { status: 503 });
        });
      })
    );
    return;
  }

  // Diğer istekler için - network first
  event.respondWith(
    fetch(request).catch(() => {
      return caches.match(request).then((cached) => {
        return cached || new Response('Not found', { status: 404 });
      });
    })
  );
});

console.log('[SW] Service worker loaded');

