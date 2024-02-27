'use strict'

const mapsIdAdd = (() => {
  // @note Affecter ou réafecter une id pour chaque carte afin d'éviter les conflits.
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

const maps = () => {
  const titleServerDefault = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
  const svgIcon =
    '<svg class="marker-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M256 14C146 14 57 102 57 211c0 172 199 295 199 295s199-120 199-295c0-109-89-197-199-197zm0 281a94 94 0 1 1 0-187 94 94 0 0 1 0 187z"/><path d="M256 14v94a94 94 0 0 1 0 187v211s199-120 199-295c0-109-89-197-199-197z"/></svg>'
  document.querySelectorAll('.map').forEach(item => {
    const map = L.map(item.id),
      el = document.getElementById(item.id),
      P = JSON.parse(el.dataset.places),
      markers = []
    L.tileLayer(el.dataset.tileserver || titleServerDefault, {
      minZoom: el.dataset.minzoom || 2,
      maxZoom: el.dataset.maxzoom || 18, // Certains jeux de tuiles sont moins profonds que d'autres, d'où l'intérêt de définir un maxZoom.
      zoom: el.dataset.zoom || el.dataset.maxzoom,
      attribution: el.dataset.attribution || '',
    }).addTo(map)
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
      //marker.openPopup()
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
  // @note Pour cette prémière stratégie on part du postulat que la librairie a été chargée en même temps que le reste du DOM, donc via un lien produit côté serveur.
  if (typeof L !== 'undefined') maps()

  document.addEventListener('readystatechange', () => {
    // @note Écoute les changement d'un document, typiquement ici l'écouteur réagira à l'injection en asynchrone du script de la bibliothèque Leaflet dans le DOM.
    if (document.readyState === 'complete' && typeof L !== 'undefined') maps()
  })
})
