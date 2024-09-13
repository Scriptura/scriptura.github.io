'use strict'

const mapsIdAdd = (() => {
  // @note Affecter ou réaffecter une id pour chaque carte afin d'éviter les conflits.
  document.querySelectorAll('.map').forEach((map, i) => {
    map.id = 'map' + i
  })
})()

// @note Permet une animation unique en CSS pour les marqueurs au lancement de la page.
const startPage = (() => {
  const html = document.documentElement,
    c = 'start-map'
  html.classList.add(c)
  window.addEventListener('load', function () {
    setTimeout(() => {
      html.classList.remove(c)
    }, 1500)
  })
})()

/**
 * Fonction qui vérifie si une tuile du serveur de tuiles est disponible.
 * @param {string} url - URL du serveur de tuiles.
 * @returns {Promise<boolean>} - Résout true si la tuile est disponible, false sinon.
 */
const checkTileServer = async url => {
  const tileUrl = url.replace('{z}', '0').replace('{x}', '0').replace('{y}', '0') // Test de la tuile (0,0,0)
  try {
    const response = await fetch(tileUrl, { method: 'GET' })
    return response.ok // Si la réponse est ok (code 2xx), le serveur est disponible
  } catch (error) {
    return false // Si une erreur survient, le serveur est considéré comme indisponible
  }
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

    // URL du serveur de tuiles à tester
    let tileServer = el.dataset.tileserver || titleServerDefault

    // Test de disponibilité du serveur de tuiles personnalisé
    const isTileServerAvailable = await checkTileServer(tileServer)

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
