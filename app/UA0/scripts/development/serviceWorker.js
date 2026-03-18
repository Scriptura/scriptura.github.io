/**
 * @file serviceWorker.js — PWA /app/UA0/
 *
 * @summary
 * Service Worker d'une PWA monopage, totalement autonome.
 * Stratégie unique : Cache First sur l'intégralité du périmètre.
 * Le réseau n'est sollicité qu'en cas de cache miss (premier chargement
 * ou invalidation via bump de CACHE_NAME).
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * STRATÉGIE
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * @strategy Cache First — {@link cacheFirst}
 *   Pipeline : cache → [miss] → réseau → écriture disque (waitUntil) → retour.
 *   En cas d'échec réseau sur un miss : retour sur OFFLINE_URL (= index.html).
 *   Invariant : l'application étant autonome et ses assets immuables entre
 *   deux versions, la fraîcheur réseau n'a aucune valeur. L'invalidation
 *   du cache est pilotée exclusivement par le bump de CACHE_NAME.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ARBITRAGES NON DÉDUCTIBLES DU CODE
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * @architectural-decision Stratégie unique sans routing
 *   L'absence de prédicat isStaticAsset est intentionnelle. Une SPA autonome
 *   n'a pas de contenu dynamique : router vers Network First pour certaines
 *   URL n'apporterait aucune fraîcheur utile et augmenterait la latence
 *   perçue à chaque navigation.
 *
 * @architectural-decision OFFLINE_URL = index.html = l'application
 *   Le fallback dégradé et le point d'entrée sont le même asset. Sur un miss
 *   réseau, retourner index.html garantit que l'application démarre quoi qu'il
 *   arrive (la SPA gère elle-même l'absence de données fraîches).
 *
 * @architectural-decision MEDIA_CACHE_NAME conservé sans alimentation
 *   Présent uniquement pour purger les entrées d'un éventuel cache media
 *   antérieur lors de activate → caches.delete. Supprimer cette constante
 *   casserait la purge sur les navigateurs ayant encore l'ancienne entrée.
 *
 * @architectural-decision putInCache + event.waitUntil
 *   L'écriture disque est détachée du return response (non bloquante pour
 *   le rendu) mais liée au cycle de vie de l'événement via event.waitUntil.
 *   Sans ce rattachement, le navigateur peut tuer le processus SW avant la
 *   fin de l'écriture, annulant silencieusement la mise en cache.
 *
 * @architectural-decision Listener 'message' absent de ce fichier
 *   La manipulation de document est interdite dans le scope SW.
 *   Enregistrer l'écoute dans le Main Thread :
 *   navigator.serviceWorker.addEventListener('message', handler)
 */

const CACHE_NAME = 'v9'
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

// --- I/O helpers ---
async function addResourcesToCache(resources) {
  try {
    const cache = await caches.open(CACHE_NAME)
    await cache.addAll(resources)
  } catch (error) {
    console.error(`Erreur cache.addAll: ${error}`)
  }
}

function putInCache(request, response) {
  return caches
    .open(CACHE_NAME)
    .then(cache => cache.put(request, response))
    .catch(error => console.error(`Erreur putInCache: ${error}`))
}

// --- Strategy ---
async function cacheFirst(event) {
  const { request } = event
  const cache = await caches.open(CACHE_NAME)
  const cached = await cache.match(request)
  if (cached) return cached

  try {
    const networkResponse = await fetch(request)
    if (networkResponse?.ok) {
      event.waitUntil(putInCache(request, networkResponse.clone()))
    }
    return networkResponse
  } catch {
    return cache.match(OFFLINE_URL)
  }
}

// --- Lifecycle ---
self.addEventListener('install', event => {
  self.skipWaiting()
  event.waitUntil(addResourcesToCache(resourcesToCache))
})

self.addEventListener('activate', event => {
  event.waitUntil(
    (async () => {
      try {
        const cacheNames = await caches.keys()
        await Promise.all(
          cacheNames
            .filter(name => name !== CACHE_NAME && name !== MEDIA_CACHE_NAME)
            .map(name => caches.delete(name)),
        )
        await self.clients.claim()
      } catch (error) {
        console.error(`Erreur activation: ${error}`)
      }
    })(),
  )
})

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return
  event.respondWith(cacheFirst(event))
})
