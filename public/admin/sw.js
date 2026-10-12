/* Shell only. The panel's work is talking to GitHub, and a stale file listing
   would be worse than no offline support at all — so the network wins and the
   cache is only what gets the page on screen. */
const SHELL = ['./', './index.html', './manifest.json'];
const CACHE = 'peditx-admin-v1';

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  event.respondWith(
    fetch(event.request)
      .catch(() => caches.match(event.request).then((hit) => hit || caches.match('./index.html')))
  );
});
