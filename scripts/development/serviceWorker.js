// @documentation @see https://developer.mozilla.org/fr/docs/Web/API/Service_Worker_API/Using_Service_Workers
// @note Ce code s'exécute dans son propre worker ou thread :


const addResourcesToCache = async resources => {
  const cache = await caches.open('v6')
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
