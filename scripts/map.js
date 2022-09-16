'use strict'

const getMapStyles = (() => { // Recommandation Leaflet de charger les styles avant les scripts.
  const styles = document.createElement('link')
  styles.setAttribute('rel', 'stylesheet')
  styles.setAttribute('href', '/libraries/leaflet/leaflet.css')
  document.head.appendChild(styles)
})()

const getLeaflet = (() => {
  const script = document.createElement('script')
  script.setAttribute('src', '/libraries/leaflet/leaflet.js')
  document.head.appendChild(script)
})()

const mapsIdAdd = (() => { // @note Affecter ou réafecter une id pour chaque carte afin d'éviter les conflits.
  let i = 1
  document.querySelectorAll('.map').forEach(function(map) {
    map.id = 'map' + i
    i++
  })
})()

// @note Permet une animation unique en CSS pour les marqueurs au lancement de la page.
const startPage = (() => {
  const html = document.documentElement,
        c = 'start-map'
  html.classList.add(c)
  window.addEventListener('load', function() {
    setTimeout(() => {
      html.classList.remove(c)
    }, 1500)
  })
})()

const maps = (() => {
  const titleServerDefault = 'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png'
  const svgIcon = '<svg class="marker-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="#E74C3C" d="M256 14C146 14 57 102 57 211c0 172 199 295 199 295s199-120 199-295c0-109-89-197-199-197zm0 281a94 94 0 1 1 0-187 94 94 0 0 1 0 187z"/><path fill="#C0392B" d="M256 14v94a94 94 0 0 1 0 187v211s199-120 199-295c0-109-89-197-199-197z"/></svg>'
  document.querySelectorAll('.map').forEach(function(item) {
    const mapInit = () => {
      const map = L.map(item.id),
            el = document.getElementById(item.id),
            P = [JSON.parse(el.dataset.places)],
            markers = []
            //console.table(P)
      L.tileLayer(
        el.dataset.tileserver || titleServerDefault, {
          minZoom: 2,
          maxZoom: el.dataset.zoom || 18, // Certains jeux de tuiles sont moins profonds que d'autres, d'où l'intérêt de définir un maxZoom.
          attribution: el.dataset.attribution || ''
        }
      ).addTo(map)
      const divIcon = L.divIcon({
        className: 'leaflet-data-marker',
        html: svgIcon,
        iconAnchor: [20, 40],
        iconSize: [40, 40],
        popupAnchor: [0, -60]
      })
      for (let i = 0; i < P.length; i++) {
        const marker = L.marker(P[i][1], {icon: divIcon})
        if (P[i][0]) marker.bindPopup(P[i][0])
        //marker.openPopup()
        marker.addTo(map)
        markers.push(marker)
      }
      const group = new L.featureGroup(markers)
      map.fitBounds(group.getBounds())
    }
    window.addEventListener('load', () => mapInit())
  })
})()
