// Ce code s'exécute dans son propre worker ou thread :

const addResourcesToCache = async (resources) => {
  const cache = await caches.open('v1')
  await cache.addAll(resources)
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    addResourcesToCache([
      '/',
      '/styles/main.css',
      '/scripts/main.js',
      '/fonts/notoSans-Regular.woff2',
      '/fonts/notoSerif-Regular.woff2'
    ])
  )
})

/*
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open('v1').then(function(cache) {
      return cache.add('/index.html');
    })
  );
});

self.addEventListener('fetch', e => {
  e.respondWith(
    caches.match(e.request).then(function(response) {
      return response || fetch(e.request);
    })
  );
});
*/

/*
self.addEventListener('install', e => {
  console.log("Service worker installed")
})

self.addEventListener('activate', e => {
  console.log("Service worker activated")
})

self.addEventListener('fetch', e => {
  console.log("Service worker fetched")
})
*/
