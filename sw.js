// Minimal service worker: enables "Add to Home Screen" installability and
// caches the app shell so previously-visited pages still open when offline.
// Deliberately simple — does NOT cache API/Supabase requests, so booking
// data is always fresh; only static pages get cached.

// Bump this on any release that changes cached static assets (icons etc.) —
// assets are served cache-first, so without a new cache name returning
// visitors keep old copies forever.
const CACHE_NAME = 'ustara-v2';
const APP_SHELL = [
  '/index.html',
  '/app-entry.html',
  '/profile.html',
  '/client-dashboard.html',
  '/barber-dashboard.html',
  '/auth.html'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Never cache Supabase API calls or cross-origin requests — booking data
  // must always be live, never stale from cache.
  if (url.origin !== self.location.origin) return;

  // Network-first for HTML pages (so updates show up quickly), falling
  // back to cache only when offline.
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          return response;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  // Cache-first for static assets (icons etc.)
  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request))
  );
});
