// Ce code s'exécute dans son propre worker ou thread :

const addResourcesToCache = async resources => {
  const cache = await caches.open('v2')
  await cache.addAll(resources)
}

self.addEventListener('install', event => {
  event.waitUntil(
    addResourcesToCache([
      '/',
      '/styles/main.css',
      '/styles/print.css',
      '/scripts/main.js',
      '/fonts/notoSans-Regular.woff2',
      '/fonts/notoSerif-Regular.woff2',
      '/sprites/util.svg',
      '/sprites/player.svg',
      '/medias/images/logo/logo.svg',
    ])
  )
})
