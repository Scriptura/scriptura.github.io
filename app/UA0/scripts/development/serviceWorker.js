const CACHE_NAME = 'v61'
const MEDIA_CACHE_NAME = `media-${CACHE_NAME}`
const ROOT_PATH = `/app/UA0/`
const OFFLINE_URL = `${ROOT_PATH}index.html`

const resourcesToCache = [
  `${ROOT_PATH}`,
  `${ROOT_PATH}styles/main.css`,
  `${ROOT_PATH}scripts/main.js`,
  `${ROOT_PATH}fonts/notoSans-Regular.woff2`,
  `${ROOT_PATH}fonts/notoSerif-Regular.woff2`,
  `${ROOT_PATH}fonts/OleoScriptSwashCaps-Regular.woff2`,
  `${ROOT_PATH}sprites/util.svg`,
  `${ROOT_PATH}medias/images/logo.svg`,
  `${ROOT_PATH}medias/images/uploads/CalvinAndHobbes.webp`,
  OFFLINE_URL,
]

// Fonction pour ajouter des ressources au cache
async function addResourcesToCache(resources) {
  try {
    const cache = await caches.open(CACHE_NAME)
    await cache.addAll(resources)
  } catch (error) {
    console.error(`Erreur lors de l'ajout des ressources au cache: ${error}`)
  }
}

// Fonction pour mettre en cache une réponse réseau
async function putInCache(request, response, cacheName = CACHE_NAME) {
  try {
    const cache = await caches.open(cacheName)
    await cache.put(request, response)
  } catch (error) {
    console.error(`Erreur lors de la mise en cache: ${error}`)
  }
}

// Fonction pour gérer l'indisponibilité du service (ajout de la classe CSS)
async function notifyServiceUnavailable() {
  try {
    const allClients = await clients.matchAll()
    allClients.forEach(client => {
      client.postMessage({ action: 'service-unavailable' })
    })
  } catch (error) {
    console.error(`Erreur lors de la notification d'indisponibilité: ${error}`)
  }
}

// Stratégie Network First avec fallback sur offline.html
async function networkFirst({ request }) {
  try {
    const networkResponse = await fetch(request)

    if (networkResponse && networkResponse.ok) {
      await putInCache(request, networkResponse.clone())
    }

    return networkResponse
  } catch (error) {
    // Ne pas loguer d'erreur (error) pour les échecs réseau prévisibles
    // console.warn(`Network first fallback: réseau indisponible ou erreur sur ${request.url}`)
    await notifyServiceUnavailable()

    const cache = await caches.open(CACHE_NAME)
    const cachedResponse = await cache.match(request)

    if (cachedResponse) {
      return cachedResponse
    } else {
      return cache.match(OFFLINE_URL)
    }
  }
}

// Ancienne stratégie Cache First pour les médias (commentée pour tester l'impact)
// async function cacheFirst({ request }) {
//   try {
//     const cache = await caches.open(MEDIA_CACHE_NAME)
//     const cachedResponse = await cache.match(request)

//     if (cachedResponse) {
//       return cachedResponse
//     }

//     const networkResponse = await fetch(request)
//     if (networkResponse && networkResponse.ok) {
//       await putInCache(request, networkResponse.clone(), MEDIA_CACHE_NAME)
//     }

//     return networkResponse

//   } catch (error) {
//     // Ne pas loguer d'erreur pour les échecs de fetch prévisibles (réseau coupé)
//     console.warn(`Cache first fallback: réseau indisponible ou erreur sur ${request.url}`)
//     return caches.match(OFFLINE_URL)
//   }
// }

// Ancienne fonction pour déterminer si la requête est une image (commentée pour test)
// function isMediaRequest(request) {
//   return (
//     request.destination === 'image' ||
//     /image/.test(request.headers.get('accept'))
//   )
// }

// Événement d'installation du Service Worker
self.addEventListener('install', event => {
  self.skipWaiting()
  event.waitUntil(addResourcesToCache(resourcesToCache))
})

// Événement d'activation pour supprimer les caches obsolètes et prendre le contrôle
self.addEventListener('activate', event => {
  event.waitUntil(
    (async () => {
      try {
        const cacheNames = await caches.keys()
        await Promise.all(
          cacheNames
            .filter(cacheName => cacheName !== CACHE_NAME && cacheName !== MEDIA_CACHE_NAME)
            .map(cacheName => caches.delete(cacheName)),
        )
        await self.clients.claim()
      } catch (error) {
        console.error(`Erreur lors de l'activation du service worker: ${error}`)
      }
    })(),
  )
})

// Gestion des requêtes de type 'fetch'
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') {
    return
  }

  // Ancienne gestion des requêtes pour les médias avec stratégie Cache First (commentée)
  // if (isMediaRequest(event.request)) {
  //   event.respondWith(cacheFirst({ request: event.request }))
  // } else {
  //   event.respondWith(networkFirst({ request: event.request }))
  // }

  // Utilisation exclusive de la stratégie Network First (médias inclus)
  event.respondWith(networkFirst({ request: event.request }))
})

// Gestion des messages envoyés par le Service Worker
self.addEventListener('message', event => {
  if (event.data && event.data.action === 'service-unavailable') {
    document.documentElement.classList.add('service-unavailable')
  }
})

/**
 * VERSION OK !
 */
/*
const CACHE_NAME = 'v33.3'
//const MEDIA_CACHE_NAME = `media-${CACHE_NAME}`
const OFFLINE_URL = '/offline.html'

const resourcesToCache = [
  '/',
  '/styles/main.css',
  '/styles/print.css',
  '/scripts/main.js',
  '/scripts/more.js',
  '/fonts/notoSans-Regular.woff2',
  '/fonts/notoSerif-Regular.woff2',
  '/sprites/util.svg',
  '/sprites/player.svg',
  '/medias/images/logo/logo.svg',
  '/offline.html' // Page de secours
]

// Fonction pour ajouter des ressources au cache
async function addResourcesToCache(resources) {
  const cache = await caches.open(CACHE_NAME)
  await cache.addAll(resources)
}

// Fonction pour mettre en cache une réponse réseau
async function putInCache(request, response) {
  const cache = await caches.open(CACHE_NAME)
  await cache.put(request, response)
}

// Fonction pour gérer l'indisponibilité du service (ajout de la classe CSS)
function notifyServiceUnavailable() {
  clients.matchAll().then(clients => {
    clients.forEach(client => {
      client.postMessage({ action: 'service-unavailable' })
    })
  })
}

// Stratégie Network First avec fallback sur offline.html
async function networkFirst({ request }) {
  try {
    // Essayer de récupérer la ressource depuis le réseau
    const networkResponse = await fetch(request)

    // Si la réponse est valide, on la met en cache
    if (networkResponse && networkResponse.ok) {
      putInCache(request, networkResponse.clone())
    }

    return networkResponse
  } catch (error) {
    // Problème réseau, envoyer la classe service-unavailable
    notifyServiceUnavailable()

    // Si la requête réseau échoue, tenter de récupérer depuis le cache
    const cache = await caches.open(CACHE_NAME)
    const cachedResponse = await cache.match(request)

    if (cachedResponse) {
      return cachedResponse
    } else {
      // Si la ressource n'est pas dans le cache, retourner la page offline.html
      return cache.match('/offline.html')
    }
  }
}

// Événement d'installation du Service Worker
self.addEventListener('install', event => {
  self.skipWaiting() // Force l'activation immédiate du nouveau Service Worker
  event.waitUntil(addResourcesToCache(resourcesToCache))
})

// Événement d'activation pour supprimer les caches obsolètes et prendre le contrôle
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames.filter(cacheName => cacheName !== CACHE_NAME).map(cacheName => caches.delete(cacheName))
      )
    }).then(() => {
      return self.clients.claim() // Prendre le contrôle immédiat des pages ouvertes
    }),
  )
})

// Gestion des requêtes de type 'fetch'
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') {
    return // Ignorer toutes les requêtes qui ne sont pas GET
  }

  event.respondWith(
    networkFirst({
      request: event.request,
    }),
  )
})

// Gestion des messages envoyés par le Service Worker
self.addEventListener('message', event => {
  if (event.data && event.data.action === 'service-unavailable') {
    // Ajouter la classe CSS sur le tag HTML
    document.documentElement.classList.add('service-unavailable')
  }
})
*/
