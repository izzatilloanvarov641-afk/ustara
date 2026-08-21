// Minimal service worker: enables "Add to Home Screen" installability and
// caches the app shell so previously-visited pages still open when offline.
// Deliberately simple — does NOT cache API/Supabase requests, so booking
// data is always fresh; only static pages get cached.

// Bump this on any release that changes cached static assets (icons etc.) —
// assets are served cache-first, so without a new cache name returning
// visitors keep old copies forever.
const CACHE_NAME = 'ustara-v4';
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
          // Only cache good responses — caching a 404/500 here would make
          // the offline fallback serve that error page forever after.
          if (response.ok) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          }
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

/* ---------- web push ----------
   Every notification is branded as coming from Ustara: our icon, our name in
   the title. `badge` is the monochrome silhouette Android puts in the status
   bar — it must be a separate flat image, the full-colour icon renders as a
   grey blob there.

   The payload is JSON written by the send-push Edge Function. If a push ever
   arrives without one (or malformed), we still show something rather than
   letting the browser display its own "This site has been updated in the
   background" placeholder. */
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = {}; }

  const title = data.title || 'Ustara';
  const options = {
    body: data.body || '',
    icon: '/icons/icon-192.png',
    badge: '/icons/badge-72.png',
    tag: data.tag || 'ustara',
    renotify: true,
    data: { url: data.url || '/client-dashboard.html' },
    actions: data.actions || []
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

/* Tapping the notification focuses an already-open Ustara tab instead of
   piling up new ones, and navigates it to the right page. */
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.navigate(target);
          return client.focus();
        }
      }
      return self.clients.openWindow(target);
    })
  );
});
