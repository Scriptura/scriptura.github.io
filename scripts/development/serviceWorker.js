// Ce code s'exécute dans son propre worker ou thread :

self.addEventListener('install', e => {
  console.log("Service worker installed")
})

self.addEventListener('activate', e => {
  console.log("Service worker activated")
})

self.addEventListener('fetch', e => {
  console.log("Service worker fetched")
})
