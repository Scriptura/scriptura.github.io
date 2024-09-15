// @documentation @see https://developer.mozilla.org/fr/docs/Web/API/Service_Worker_API/Using_Service_Workers
// @note Ce code s'exécute dans son propre worker ou thread :

/**
 * Ajoute les ressources spécifiées au cache
 * @param {Array<string>} resources - Les URLs des ressources à mettre en cache
 * @returns {Promise<void>}
 */
async function addResourcesToCache(resources) {
  const cache = await caches.open('v10')
  await cache.addAll(resources)
}

/**
 * Gestion de l'événement d'installation du Service Worker
 */
self.addEventListener('install', event => {
  event.waitUntil(
    addResourcesToCache([
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
    ]),
  )
})

/**
 * Met en cache une réponse pour une requête spécifique
 * @param {Request} request - La requête à mettre en cache
 * @param {Response} response - La réponse à mettre en cache
 * @returns {Promise<void>}
 */
async function putInCache(request, response) {
  const cache = await caches.open('v1') // Utilise le même cache que lors de l'installation
  await cache.put(request, response) // Met la réponse en cache pour la requête
}

/**
 * Stratégie de mise en cache "cache first"
 * @param {Request} request - La requête à traiter
 * @param {string} fallbackUrl - URL de secours à utiliser en cas d'échec de la récupération
 * @returns {Promise<Response>} La réponse à fournir au navigateur
 */
async function cacheFirst({ request, fallbackUrl }) {
  // Tente de récupérer la réponse depuis le cache
  const responseFromCache = await caches.match(request)
  if (responseFromCache) {
    return responseFromCache
  }

  // Si la réponse n'est pas dans le cache, tente de la récupérer depuis le réseau
  try {
    const responseFromNetwork = await fetch(request)
    // Clone la réponse pour mettre une copie en cache et renvoyer l'originale
    await putInCache(request, responseFromNetwork.clone())
    return responseFromNetwork
  } catch (error) {
    // Si la récupération depuis le réseau échoue, utilise l'URL de secours si disponible
    const fallbackResponse = await caches.match(fallbackUrl)
    if (fallbackResponse) {
      return fallbackResponse
    }
    // En cas d'absence de réponse de secours, retourne une réponse d'erreur générique
    return new Response("Une erreur réseau s'est produite", {
      status: 408,
      headers: { 'Content-Type': 'text/plain' },
    })
  }
}

/**
 * Gestion de l'événement de récupération des requêtes
 */
self.addEventListener('fetch', event => {
  event.respondWith(
    cacheFirst({
      request: event.request,
      fallbackUrl: '/medias/images/demo/test-original.webp', // URL de secours à utiliser en cas d'échec
    }),
  )
})
