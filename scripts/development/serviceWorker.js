// @documentation @see https://developer.mozilla.org/fr/docs/Web/API/Service_Worker_API/Using_Service_Workers

const CACHE_NAME = 'v28'

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

// Fonction pour vérifier si une réponse est corrompue (en utilisant type MIME)
async function isCorrupted(response) {
  if (!response || !response.ok) return true

  try {
    const clonedResponse = response.clone()
    const contentType = clonedResponse.headers.get('Content-Type')

    // Vérification du type MIME pour les vidéos, images, etc.
    if (contentType && (contentType.startsWith('video/') || contentType.startsWith('image/'))) {
      const contentLength = clonedResponse.headers.get('Content-Length')
      if (contentLength && parseInt(contentLength, 10) < 1024) {
        return true // Le fichier semble corrompu s'il est trop petit
      }
    }

    return false
  } catch (error) {
    return true
  }
}

// Stratégie Network First
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
    // Si la requête réseau échoue, tenter de récupérer depuis le cache
    const cache = await caches.open(CACHE_NAME)
    const cachedResponse = await cache.match(request)

    if (cachedResponse) {
      return cachedResponse
    } else {
      return new Response("Une erreur réseau s'est produite et la ressource n'est pas dans le cache.", {
        status: 408,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      })
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
        cacheNames
          .filter(cacheName => cacheName !== CACHE_NAME)
          .map(cacheName => caches.delete(cacheName))
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
