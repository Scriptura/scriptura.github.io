// @documentation @see https://developer.mozilla.org/fr/docs/Web/API/Service_Worker_API/Using_Service_Workers

const addResourcesToCache = async resources => {
  const cache = await caches.open('v14')
  await cache.addAll(resources)
}

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

/*
const putInCache = async (request, response) => {
  const cache = await caches.open('v4');
  await cache.put(request, response);
};

const cacheFirst = async ({ request, preloadResponsePromise, fallbackUrl }) => {
  // Pour commencer on essaie d'obtenir la ressource depuis le cache
  const responseFromCache = await caches.match(request);
  if (responseFromCache) {
    return responseFromCache;
  }

  // Ensuite, on tente de l'obtenir du réseau
  try {
    const responseFromNetwork = await fetch(request);
    // Une réponse ne peut être utilisée qu'une fois
    // On la clone pour en mettre une copie en cache
    // et servir l'originale au navigateur
    putInCache(request, responseFromNetwork.clone());
    return responseFromNetwork;
  } catch (error) {
    const fallbackResponse = await caches.match(fallbackUrl);
    if (fallbackResponse) {
      return fallbackResponse;
    }
    // Quand il n'y a même pas de contenu par défaut associé
    // on doit tout de même renvoyer un objet Response
    return new Response("Une erreur réseau s'est produite", {
      status: 408,
      headers: { "Content-Type": "text/plain" },
    });
  }
};

self.addEventListener('fetch', (event) => {
  event.respondWith(
    cacheFirst({
      request: event.request,
      fallbackUrl: '/medias/images/demo/test-original.webp',
    }),
  );
});
*/

//////////////////// NOUVELLE SOLUTION, GÉNIALE POUR LE CACHE, MAIS PROVOQUE DES ERREURS 408 AUX POSTS : ////////////////////////

/*
// Fonction pour ajouter des ressources au cache
async function addResourcesToCache(resources) {
  const cache = await caches.open('v11')
  await cache.addAll(resources)
}

// Fonction pour vérifier si une ressource est corrompue
async function isCorrupted(response) {
  if (!response || !response.ok) return true

  try {
    // Par exemple, on vérifie si la taille de la vidéo dépasse un certain seuil.
    const clonedResponse = response.clone()
    const contentLength = clonedResponse.headers.get('Content-Length')

    // Si la taille du fichier est petite, il peut être corrompu (par exemple < 100 octets)
    if (contentLength && parseInt(contentLength, 10) < 100) {
      return true
    }

    return false
  } catch (error) {
    // Si une erreur survient durant la vérification, considérer comme corrompu
    return true
  }
}

// Fonction pour mettre une ressource en cache
async function putInCache(request, response) {
  const cache = await caches.open('v11')
  await cache.put(request, response)
}

// Fonction pour gérer le cache avec fallback réseau
async function cacheThenNetwork(request) {
  const cache = await caches.open('v11')
  const cachedResponse = await cache.match(request)

  // Vérification de l'intégrité du fichier
  if (cachedResponse && !(await isCorrupted(cachedResponse))) {
    return cachedResponse
  }

  // Si le fichier est corrompu ou absent, on tente de le récupérer depuis le réseau
  try {
    const networkResponse = await fetch(request)

    // Si la réponse réseau est valide, la mettre en cache
    if (networkResponse && networkResponse.ok) {
      putInCache(request, networkResponse.clone())
      return networkResponse
    }

    // Si la réponse réseau n'est pas valide, retourner l'ancienne (corrompue) si possible
    return cachedResponse || new Response('Ressource non disponible et fichier corrompu.', { status: 408 })
  } catch (error) {
    // Si la récupération réseau échoue, retourner le cache même corrompu si possible
    return cachedResponse || new Response('Ressource non disponible hors ligne.', { status: 408 })
  }
}

// Mise en cache initiale des ressources lors de l'installation du Service Worker
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
      // Ajoutez d'autres fichiers si nécessaire
    ]),
  )
})

// Gestion des requêtes via le Service Worker
self.addEventListener('fetch', event => {
  event.respondWith(cacheThenNetwork(event.request))
})
*/
