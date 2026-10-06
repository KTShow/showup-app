// ============================================================
// sw.js — ShowUp service worker: alerts only
// ============================================================
// Receives Web Push alerts sent by /api/push and shows them; a tap opens
// (or focuses) ShowUp at the alert's link. Deliberately has NO fetch
// handler and caches nothing, so it can never serve a stale index.html --
// the "edit, push, it's live" workflow is unaffected.
// ============================================================

self.addEventListener('install', function() { self.skipWaiting(); });
self.addEventListener('activate', function(e) { e.waitUntil(self.clients.claim()); });

self.addEventListener('push', function(e) {
  var d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || 'ShowUp', {
    body: d.body || '',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    tag: d.tag || undefined,
    renotify: !!d.tag,
    data: { url: d.url || '/' },
  }));
});

self.addEventListener('notificationclick', function(e) {
  e.notification.close();
  var url = new URL((e.notification.data && e.notification.data.url) || '/', self.location.origin).href;
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(list) {
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      if (c.url.indexOf(self.location.origin) === 0 && 'focus' in c) {
        c.postMessage({ type: 'open-url', url: url });
        return c.focus();
      }
    }
    return self.clients.openWindow(url);
  }));
});
