const CACHE_NAME = 'cinelog-v2';
const OFFLINE_URL = '/';
const NO_CACHE_PREFIXES = ['/admin', '/users', '/watchlists', '/u/', '/profil/', '/search/suggestions'];
const STATIC_DESTINATIONS = new Set(['style', 'script', 'image', 'font', 'manifest']);

// Core assets to cache immediately on install
const PRECACHE_ASSETS = [
  '/',
  '/icon.png',
  '/icon-192.png',
  '/icon-maskable.png',
  '/apple-touch-icon.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(PRECACHE_ASSETS).catch((err) => {
        console.warn('PWA precache error:', err);
      });
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }
        })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  // Only handle GET requests
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);

  // Skip non-http/https requests
  if (!url.protocol.startsWith('http')) return;

  // Do not cache admin, authentication, or user-specific dynamic routes
  if (NO_CACHE_PREFIXES.some((prefix) => url.pathname.startsWith(prefix))) {
    return;
  }

  // HTML page navigations: Network First, fallback to cache
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response.status === 200 && url.origin === self.location.origin) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return response;
        })
        .catch(() => {
          return caches.match(event.request).then((cached) => {
            return cached || caches.match(OFFLINE_URL);
          });
        })
    );
    return;
  }

  // Only cache static assets (never Turbo Drive / HTML / Turbo Stream fetches)
  const isStaticAsset = STATIC_DESTINATIONS.has(event.request.destination) || url.pathname.startsWith('/assets/');
  if (!isStaticAsset) {
    return;
  }

  // Static assets (images, styles, scripts): Stale-While-Revalidate
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      const fetchPromise = fetch(event.request)
        .then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200 && networkResponse.type === 'basic') {
            const copy = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return networkResponse;
        })
        .catch(() => cachedResponse);

      return cachedResponse || fetchPromise;
    })
  );
});
