'use strict'

/**
 * @file map.js
 * @description Gestionnaire de cartes Leaflet orienté Data-First.
 *
 * Pipeline général :
 *   1. `collectMapConfigs`  — extraction DOM unique, production du dataset structuré.
 *   2. `observeMaps`        — IntersectionObserver, déclencheur de l'init lazy.
 *   3. `resolveTileServer`  — sonde parallèle, sélection du serveur le plus rapide.
 *   4. `initMap`            — instanciation Leaflet et rendu des marqueurs.
 *
 * @strategy        Séparation stricte data / logic : toutes les données sont
 *                  extraites et structurées avant que la moindre logique Leaflet
 *                  ne s'exécute. Aucune lecture de dataset ne se produit après
 *                  la phase de collecte.
 *
 * @architectural-decision Leaflet est considéré comme une dépendance externe
 *                  non contrôlée (chargement async possible). Le script expose
 *                  `window.initMaps` comme point d'entrée public pour les cas
 *                  où `L` n'est pas encore disponible à l'événement `load`.
 *                  Le MutationObserver sur le `head` est supprimé : il transférait
 *                  la responsabilité du timing au script lui-même plutôt qu'au
 *                  site appelant, rendant le comportement difficile à auditer.
 */

// ─── Constantes immuables ────────────────────────────────────────────────────

/** @type {string} URL du serveur OSM public, utilisée comme fallback garanti. */
const TILE_DEFAULT = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'

/**
 * Coordonnées d'une tuile existante et stable, utilisée pour les sondes HEAD.
 * La tuile z=16/x=33440/y=23491 couvre une zone urbaine dense en Europe
 * occidentale, garantissant sa présence sur tout serveur OSM conforme.
 *
 * @type {{ z: string, x: string, y: string }}
 */
const TILE_PROBE = Object.freeze({ z: '16', x: '33440', y: '23491' })

/**
 * Markup SVG du marqueur de carte, déclaré comme constante module-level.
 *
 * @architectural-decision Hors de toute boucle pour éviter la réallocation
 *                  répétée d'une chaîne identique. String statique : zéro coût
 *                  de clonage entre instances de marqueurs, Leaflet ne mute pas
 *                  la valeur passée à `html`.
 *
 * @type {string}
 */
const SVG_ICON =
  '<svg class="marker-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">' +
  '<path d="M256 14C146 14 57 102 57 211c0 172 199 295 199 295s199-120 199-295c0-109-89-197-199-197zm0 281a94 94 0 1 1 0-187 94 94 0 0 1 0 187z"/>' +
  '<path d="M256 14v94a94 94 0 0 1 0 187v211s199-120 199-295c0-109-89-197-199-197z"/>' +
  '</svg>'

/** @type {string} Classe CSS déclenchant l'animation d'entrée des marqueurs. */
const ANIM_CLASS = 'start-map'

/**
 * Durée de l'animation d'entrée en millisecondes.
 *
 * @architectural-decision `classList.remove` est appelé via `setTimeout` plutôt
 *                  que sur `animationend` : évite un listener supplémentaire par
 *                  carte et reste correct même si l'animation CSS est désactivée
 *                  (préférence `prefers-reduced-motion`).
 *
 * @type {number}
 */
const ANIM_DURATION = 1500

/**
 * Sous-domaines à sonder pour les serveurs de tuiles avec template `{s}`.
 * @type {ReadonlyArray<string>}
 */
const SUBDOMAINS = Object.freeze(['a', 'b', 'c'])

// ─── Lazy singleton divIcon ──────────────────────────────────────────────────

/** @type {L.DivIcon|null} Instance unique partagée entre tous les marqueurs. */
let _divIcon = null

/**
 * Retourne le `L.DivIcon` partagé, en le créant à la première invocation.
 *
 * @strategy        Lazy singleton via `??=` : instanciation différée jusqu'après
 *                  le boot de Leaflet, sans surcoût de vérification conditionnelle
 *                  explicite aux appels suivants.
 *
 * @architectural-decision Un `DivIcon` unique est partagé par tous les marqueurs
 *                  de toutes les cartes. Leaflet ne mute pas l'objet icon après
 *                  la création du marker : le partage est sans risque. Coût mémoire
 *                  : O(1) au lieu de O(n marqueurs).
 *
 * @returns {L.DivIcon}
 */
const getDivIcon = () =>
  (_divIcon ??= L.divIcon({
    className:   'leaflet-data-marker',
    html:        SVG_ICON,
    iconAnchor:  [20, 40],
    iconSize:    [40, 40],
    popupAnchor: [0, -60],
  }))

// ─── Single-pass DOM extraction ──────────────────────────────────────────────

/**
 * @typedef {Object} MapConfig
 * @property {HTMLElement}   el          - Élément DOM `.map`.
 * @property {string}        id          - Identifiant affecté à l'élément (`map0`, `map1`, …).
 * @property {string|null}   tileServer  - Template URL du serveur de tuiles custom, ou `null`.
 * @property {number|string} minZoom     - Zoom minimum (défaut : 2).
 * @property {number|string} maxZoom     - Zoom maximum (défaut : 18).
 * @property {string|null}   zoom        - Zoom fixe post-fitBounds, ou `null`.
 * @property {string}        attribution - Texte d'attribution cartographique.
 * @property {string}        placesRaw   - Sérialisation JSON des marqueurs, non parsée.
 */

/**
 * Parcourt le DOM une seule fois pour produire le tableau des configurations.
 * Affecte également les ids stables sur les éléments `.map`.
 *
 * @strategy        Single-pass : une unique `querySelectorAll` alimente à la fois
 *                  l'affectation des ids et la construction du dataset structuré.
 *                  Zéro lecture de dataset ne se produira après cette fonction.
 *
 * @architectural-decision `placesRaw` est conservé en string à ce stade.
 *                  `JSON.parse` est coûteux et inutile tant que la carte n'est pas
 *                  visible : le parse est donc délégué à `initMap`, déclenchée
 *                  uniquement quand l'observer valide la visibilité.
 *
 * @returns {MapConfig[]}
 */
const collectMapConfigs = () =>
  Array.from(document.querySelectorAll('.map'), (el, i) => {
    el.id = 'map' + i
    return {
      el,
      id:          'map' + i,
      tileServer:  el.dataset.tileserver  || null,
      minZoom:     el.dataset.minzoom     || 2,
      maxZoom:     el.dataset.maxzoom     || 18,
      zoom:        el.dataset.zoom        || null,
      attribution: el.dataset.attribution || '',
      placesRaw:   el.dataset.places,
    }
  })

// ─── Résolution du serveur de tuiles (parallèle) ─────────────────────────────

/**
 * Sonde le serveur de tuiles fourni et retourne le template utilisable,
 * ou `TILE_DEFAULT` en cas d'échec ou d'absence de template.
 *
 * @strategy        `Promise.any` sur les sous-domaines disponibles : la première
 *                  réponse HTTP 2xx gagne. Pas d'attente séquentielle, pas de
 *                  retry — si un sous-domaine répond, le serveur est opérationnel.
 *
 * @architectural-decision Méthode HEAD au lieu de GET : le corps de la tuile
 *                  (~10–30 Ko) n'est pas téléchargé. La sonde mesure uniquement
 *                  la disponibilité du serveur, pas la qualité des données.
 *
 * @architectural-decision La fonction retourne le `template` original, pas
 *                  l'URL de la tuile sondée. Leaflet a besoin du template avec
 *                  `{z}/{x}/{y}` pour générer dynamiquement toutes les tuiles
 *                  de la carte.
 *
 * @architectural-decision Pas d'`AbortController` sur les requêtes perdantes :
 *                  pour trois sous-domaines en HEAD le coût résiduel est
 *                  négligeable. À réévaluer si le pool de sous-domaines s'agrandit.
 *
 * @param {string|null} template - Template URL du serveur custom, avec éventuellement `{s}`.
 * @returns {Promise<string>} Template résolu, ou `TILE_DEFAULT`.
 */
const resolveTileServer = async (template) => {
  if (!template) return TILE_DEFAULT

  const buildProbeUrl = (tmpl, subdomain = '') =>
    tmpl
      .replace('{s}', subdomain)
      .replace('{z}', TILE_PROBE.z)
      .replace('{x}', TILE_PROBE.x)
      .replace('{y}', TILE_PROBE.y)

  const probe = (url) =>
    fetch(url, { method: 'HEAD' }).then(r => {
      if (!r.ok) throw new Error(r.status)
      return template
    })

  const candidates = template.includes('{s}')
    ? SUBDOMAINS.map(s => probe(buildProbeUrl(template, s)))
    : [probe(buildProbeUrl(template))]

  try {
    return await Promise.any(candidates)
  } catch {
    return TILE_DEFAULT
  }
}

// ─── Initialisation Leaflet ───────────────────────────────────────────────────

/**
 * Instancie la carte Leaflet et pose les marqueurs pour une configuration donnée.
 * Appelée uniquement quand l'élément est visible (threshold 0.5).
 *
 * @strategy        Lazy init : `JSON.parse`, instanciation Leaflet et résolution
 *                  réseau sont tous déclenchés ici, après confirmation de la
 *                  visibilité. Une carte hors-viewport ne consomme aucune
 *                  ressource CPU ni réseau.
 *
 * @architectural-decision `L.latLngBounds()` est accumulé directement pendant
 *                  le parcours des marqueurs. Élimine le tableau `markers[]`
 *                  intermédiaire qui n'existait que pour alimenter
 *                  `featureGroup.getBounds()`. Coût : O(n) identique, un objet
 *                  alloué en moins.
 *
 * @architectural-decision Le fallback `tileerror` est conditionnel :
 *                  si `resolvedServer === TILE_DEFAULT`, l'événement est ignoré
 *                  pour éviter une boucle d'ajout de layers identiques.
 *
 * @param {MapConfig} config
 * @returns {Promise<void>}
 */
const initMap = async (config) => {
  const { el, id, tileServer, minZoom, maxZoom, zoom, attribution, placesRaw } = config

  const places = JSON.parse(placesRaw)

  const map            = L.map(id)
  const resolvedServer = await resolveTileServer(tileServer)

  const tileLayer = L.tileLayer(resolvedServer, { minZoom, maxZoom, attribution }).addTo(map)

  tileLayer.on('tileerror', () => {
    if (resolvedServer !== TILE_DEFAULT) {
      L.tileLayer(TILE_DEFAULT, { minZoom, maxZoom, attribution }).addTo(map)
    }
  })

  const icon   = getDivIcon()
  const bounds = L.latLngBounds()

  for (const [popup, latlng] of places) {
    bounds.extend(latlng)
    const marker = L.marker(latlng, { icon })
    if (popup) marker.bindPopup(popup)
    marker.addTo(map)
  }

  map.fitBounds(bounds)
  if (zoom) map.setZoom(Number(zoom))
}

// ─── Intersection Observer ────────────────────────────────────────────────────

/**
 * Crée un `IntersectionObserver` unique couvrant toutes les cartes.
 * Fusionne la logique d'animation et d'init Leaflet dans un seul callback.
 *
 * @strategy        Observer unique partagé : un seul objet browser pour N cartes,
 *                  au lieu de N observers indépendants. Le dispatch vers la config
 *                  correcte est assuré par une `Map<Element, MapConfig>` en O(1).
 *
 * @architectural-decision `pending` (`Map<Element, MapConfig>`) remplace une
 *                  recherche linéaire dans le tableau `configs` à chaque callback.
 *                  L'entrée est supprimée après init : libère la référence à la
 *                  config et empêche une double initialisation si l'observer
 *                  délivre l'entrée plus d'une fois.
 *
 * @architectural-decision Animation et init sont fusionnés dans le même observer
 *                  plutôt que séparés en deux observers distincts. Ils partagent
 *                  le même seuil (0.5) et le même cycle de vie (`unobserve` après
 *                  déclenchement). La fusion supprime un observer et un callback
 *                  redondants.
 *
 * @architectural-decision L'absence de reflow sur l'animation est une contrainte
 *                  CSS, pas JS. Le script ne peut la garantir : `.start-map` ne
 *                  doit animer que `transform` et/ou `opacity` (propriétés
 *                  composites, traitées hors du thread de layout).
 *
 * @param {MapConfig[]} configs
 * @returns {void}
 */
const observeMaps = (configs) => {
  const pending = new Map(configs.map(c => [c.el, c]))

  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting || entry.intersectionRatio < 0.5) continue

        const el     = entry.target
        const config = pending.get(el)
        if (!config) continue

        el.classList.add(ANIM_CLASS)
        setTimeout(() => el.classList.remove(ANIM_CLASS), ANIM_DURATION)

        initMap(config)

        pending.delete(el)
        observer.unobserve(el)
      }
    },
    { threshold: 0.5 },
  )

  for (const { el } of configs) observer.observe(el)
}

// ─── Bootstrap ────────────────────────────────────────────────────────────────

/**
 * Point d'entrée unique du module.
 * Vérifie la disponibilité de Leaflet, collecte les configs et arme l'observer.
 *
 * @strategy        Déclenchement sur `load` (chemin nominal) + exposition via
 *                  `window.initMaps` (chemin alternatif si Leaflet est injecté
 *                  async après `load`).
 *
 * @architectural-decision Le `MutationObserver` sur `document.head` est supprimé.
 *                  Raisons : (1) observe le DOM global pour détecter un seul
 *                  script tiers, disproportionné ; (2) le timeout de 10 s est
 *                  arbitraire et silencieux en cas d'échec ; (3) transfère au
 *                  script une responsabilité qui appartient au site appelant.
 *                  Contrat de remplacement : si Leaflet arrive après `load`,
 *                  appeler `window.initMaps()` explicitement.
 *
 * @returns {void}
 */
const bootstrap = () => {
  if (typeof L === 'undefined') return
  const configs = collectMapConfigs()
  if (configs.length) observeMaps(configs)
}

/** @type {() => void} Point d'entrée public pour init manuelle post-`load`. */
window.initMaps = bootstrap
window.addEventListener('load', bootstrap)
