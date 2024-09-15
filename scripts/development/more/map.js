'use strict'

const mapsIdAdd = (() => {
  // @note Affecter ou réaffecter une id pour chaque carte afin d'éviter les conflits.
  document.querySelectorAll('.map').forEach((map, i) => {
    map.id = 'map' + i
  })
})()

// @note Permet une animation unique en CSS pour les marqueurs lorsque la carte est visible par l'utilisateur.
const startPage = (() => {
  const c = 'start-map'

  // Sélectionner toutes les cartes avec la classe .map.
  const mapElements = document.querySelectorAll('.map')

  // Création de l'observer pour chaque carte.
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting && entry.intersectionRatio >= 0.5) {
        const map = entry.target
        map.classList.add(c)

        // Lancer l'animation et retirer la classe après 1,5 seconde.
        setTimeout(() => {
          map.classList.remove(c)
        }, 1500)

        // On arrête d'observer la carte une fois l'animation déclenchée.
        observer.unobserve(map)
      }
    })
  }, { threshold: [0.5] }) // Les cartes doivent être visibles à 50%.

  // Observer chaque carte.
  mapElements.forEach(map => {
    observer.observe(map)
  })
})()

/**
 * Fonction qui vérifie la disponibilité d'une tuile sur un serveur de tuiles spécifique avec une stratégie de retry.
 * @param {string} urlTemplate - Modèle d'URL du serveur de tuiles avec des sous-domaines {s}.
 * @param {Array<string>} subdomains - Liste des sous-domaines à tester (e.g. ['a', 'b', 'c']).
 * @param {number} retries - Nombre de tentatives par sous-domaine.
 * @param {number} delay - Délai entre chaque tentative en millisecondes.
 * @returns {Promise<boolean>} - Résout true si la tuile est disponible, false sinon.
 */
const checkTileServerWithSubdomainsAndRetry = async (urlTemplate, subdomains = ['a', 'b', 'c'], retries = 3, delay = 1000) => {
  for (const subdomain of subdomains) {
    const tileUrl = urlTemplate.replace('{s}', subdomain).replace('{z}', '16').replace('{x}', '33440').replace('{y}', '23491') // Test d'une tuile existante

    for (let attempt = 1; attempt <= retries; attempt++) {
      try {
        const response = await fetch(tileUrl, { method: 'GET' })
        //console.log(response) => retournera un JSON, avec notamment l'état du serveur (200, etc) et l'URL d'une tuile à tester.
        if (response.ok) {
          console.log(`Map : chargement des tuiles.`)
          return true
        }
      } catch (error) {
        console.error(`Map : échec du chargement des tuiles ; une nouvelle tentative de chargement va débuter...`)
      }
      // Attendre avant de réessayer
      await new Promise(resolve => setTimeout(resolve, delay))
    }
  }
  console.error(`Map : serveur de tuiles indisponible.`)
  return false
}

const maps = async () => {
  const titleServerDefault = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
  const svgIcon =
    '<svg class="marker-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M256 14C146 14 57 102 57 211c0 172 199 295 199 295s199-120 199-295c0-109-89-197-199-197zm0 281a94 94 0 1 1 0-187 94 94 0 0 1 0 187z"/><path d="M256 14v94a94 94 0 0 1 0 187v211s199-120 199-295c0-109-89-197-199-197z"/></svg>'

  document.querySelectorAll('.map').forEach(async item => {
    const map = L.map(item.id),
      el = document.getElementById(item.id),
      P = JSON.parse(el.dataset.places),
      markers = []

    // URL du serveur de tuiles à tester (avec sous-domaines pour OSM France)
    let tileServer = el.dataset.tileserver || titleServerDefault

    // Test de disponibilité du serveur de tuiles personnalisé avec retry (et sous-domaines)
    const isTileServerAvailable = await checkTileServerWithSubdomainsAndRetry(tileServer)

    // Si le serveur de tuiles personnalisé n'est pas disponible, on passe au serveur par défaut
    if (!isTileServerAvailable) {
      tileServer = titleServerDefault
    }

    // Ajout des tuiles à la carte
    const tileLayer = L.tileLayer(tileServer, {
      minZoom: el.dataset.minzoom || 2,
      maxZoom: el.dataset.maxzoom || 18,
      zoom: el.dataset.zoom || el.dataset.maxzoom,
      attribution: el.dataset.attribution || '',
    }).addTo(map)

    // Gestion de l'erreur de tuiles (fallback vers serveur par défaut si une tuile échoue)
    tileLayer.on('tileerror', () => {
      console.error('Erreur de tuile. Basculement vers le serveur par défaut.')
      L.tileLayer(titleServerDefault).addTo(map)
    })

    const divIcon = L.divIcon({
      className: 'leaflet-data-marker',
      html: svgIcon,
      iconAnchor: [20, 40],
      iconSize: [40, 40],
      popupAnchor: [0, -60],
    })

    for (let i = 0; i < P.length; i++) {
      const marker = L.marker(P[i][1], { icon: divIcon })
      if (P[i][0]) marker.bindPopup(P[i][0])
      marker.addTo(map)
      markers.push(marker)
    }

    const group = new L.featureGroup(markers)
    map.fitBounds(group.getBounds())
    el.dataset.zoom && map.setZoom(el.dataset.zoom)
  })
}

/**
 * Test la présence de la bibliothèque Leaflet.js chargée en asynchrone et, si oui, exécution du script de configuration.
 * @param {object} L est une variable globale produite par Leaflet, elle nous permettra de tester l'initialisation de la bibliothèque.
 * @note typeof permet de tester la variable sans que celle-ci produise une erreur si elle n'est pas définie.
 */
window.addEventListener('load', () => {
  if (typeof L !== 'undefined') maps()

  document.addEventListener('readystatechange', () => {
    if (document.readyState === 'complete' && typeof L !== 'undefined') maps()
  })
})
