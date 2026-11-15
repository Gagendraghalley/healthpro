// Health Pro's service worker: push notifications. It shows each one, and a
// tap opens the page it's about (in the open app, or a new window).
//
// It replaces Flutter's own service worker (web/flutter_bootstrap.js loads
// the app without it), so there's no offline cache: every visit gets the
// newest app.
'use strict';

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // Flutter's old caches, from before.
    for (const name of await caches.keys()) {
      if (name.startsWith('flutter-')) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  event.waitUntil(self.registration.showNotification(data.title || 'Health Pro', {
    body: data.body || '',
    icon: 'icons/Icon-192.png',
    tag: data.id || undefined,
    data: { link: data.link || '/notifications' },
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const link = (event.notification.data && event.notification.data.link) || '/notifications';
  const url = new URL(self.registration.scope);
  url.hash = link;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if (client.url.startsWith(self.registration.scope)) {
        await client.focus();
        if ('navigate' in client) await client.navigate(url.href);
        return;
      }
    }
    await self.clients.openWindow(url.href);
  })());
});
