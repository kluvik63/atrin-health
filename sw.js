/* ATRIN LAB · Health Tracker · Service Worker v2
   Cache-first for app shell · network-first with cache fallback for CDN */

const CACHE_NAME = 'atrin-health-v2';

const APP_SHELL = [
  './',
  './index.html',
  './config.js',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './apple-touch-icon.png',
  './favicon.ico'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((c) => c.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Don't cache Supabase API calls — always go to network
  if (url.hostname.includes('supabase.co')) return;

  const isAppShell = APP_SHELL.some(
    (path) => url.pathname.endsWith(path.replace('./', '/'))
  ) || url.pathname === '/' || url.pathname.endsWith('/index.html');

  if (isAppShell) {
    event.respondWith(
      caches.match(req).then((cached) =>
        cached || fetch(req).then((resp) => {
          const c = resp.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(req, c));
          return resp;
        })
      )
    );
  } else {
    event.respondWith(
      fetch(req).then((resp) => {
        if (resp.ok && (
          url.origin.includes('esm.sh') ||
          url.origin.includes('unpkg.com') ||
          url.origin.includes('cdn.tailwindcss.com') ||
          url.origin.includes('jspm.io')
        )) {
          const c = resp.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(req, c));
        }
        return resp;
      }).catch(() => caches.match(req))
    );
  }
});
