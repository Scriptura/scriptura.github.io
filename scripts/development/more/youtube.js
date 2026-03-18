'use strict'

/**
 * youtube.js — Architecture ECS/DOD (Zero-API Google)
 * ─────────────────────────────────────────────────────────────────────────
 *
 * Stratégie : endpoint oEmbed public YouTube (sans clé API, sans quota).
 * @see https://youtube.com/oembed?url=http://www.youtube.com/watch?v={id}&format=json
 *
 * Pipeline par entité :
 *   bootstrap() → FetchSystem → dataStore[id] → UIRenderSystem → DOM
 *   Input (click) → CommandBuffer → CommandSystem → transition PLAYING
 *
 * ─────────────────────────────────────────────────────────────────────────
 * INVARIANTS STRUCTURELS
 * ─────────────────────────────────────────────────────────────────────────
 *
 * INV-1  DOM = buffer de sortie exclusif. UIRenderSystem est le seul
 *        système autorisé à injecter des nœuds.
 *
 * INV-2  Zéro innerHTML dynamique à runtime. Deux templates AOT parsés
 *        une fois au chargement ; cloneNode(true) à chaque instanciation.
 *
 * INV-3  Zéro listener par instance. Un listener click global délégué
 *        sur document résout l'action via data-action + data-entity-id.
 *
 * INV-4  AbortController par entité. Un seul abort() annule le fetch
 *        en cours ET invalide le listener d'interaction.
 *
 * INV-5  dataStore est la source de vérité. Le DOM ne contient aucune
 *        donnée : ni titre, ni URL, ni état de lecture.
 *
 * ─────────────────────────────────────────────────────────────────────────
 * ARBITRAGES ET COMPROMIS
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ARB-1  FLAG D'ÉTAT vs FLAG DIRTY
 *
 *   Option rejetée : flag dirty binaire (pattern mediaPlayer.js).
 *
 *   Raison du rejet :
 *     dirty est utile dans une boucle RAF à 60fps pour éviter les WRITE
 *     inutiles sur des entités dont l'état n'a pas changé. Ici il n'y a
 *     pas de boucle RAF — le rendu est déclenché une seule fois par entité,
 *     après résolution asynchrone du fetch. Un dirty binaire n'apporterait
 *     aucune économie de frame : il n'y a pas de frame.
 *
 *   Décision : machine d'états explicite à quatre valeurs.
 *     PENDING  → fetch en cours, aucune interaction possible.
 *     READY    → fetch résolu, vignette rendue, bouton play actif.
 *     PLAYING  → iframe injectée, vignette retirée.
 *     ERROR    → fetch échoué, UI d'erreur rendue.
 *   Les transitions sont les seuls moments de WRITE DOM. L'état est la
 *   garde qui empêche une transition illégitime (ex: double-clic play).
 *
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ARB-2  TEMPLATE IFRAME vs CREATEELEMENT
 *
 *   Option rejetée : HTMLTemplateElement pour l'iframe.
 *
 *   Raison du rejet :
 *     L'iframe est créée une seule fois par entité, lors de la transition
 *     PLAYING. Elle n'est pas instanciée en boucle. Un template ne ferait
 *     que déplacer le createElement dans le parsing du template, sans gain
 *     de parsing O(1) puisqu'il n'y a qu'une occurrence.
 *     De plus, src et title sont des valeurs dynamiques (issues du store)
 *     qui doivent être injectées après le clone de toute façon.
 *
 *   Décision : createElement direct dans le handler PLAY, les attributs
 *   sont assignés depuis dataStore[id] exclusivement.
 *
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ARB-3  ABORT CONTROLLER : USAGE DOUBLE
 *
 *   Un seul AbortController par entité couvre deux usages distincts :
 *     a. fetch : signal passé en option à fetch(), annulé si dispose()
 *        est appelé avant la résolution.
 *     b. listeners : signal passé à addEventListener(), invalide le
 *        listener global délégué si l'entité est détruite.
 *   Un seul abort() suffit à nettoyer les deux. Pas de sur-allocation.
 *
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ARB-4  PAS DE RAF / ENGINE
 *
 *   Le pipeline de mediaPlayer.js repose sur un Engine RAF car l'état
 *   hardware (currentTime, buffered) mute en continu à 60fps. Ici, les
 *   mutations d'état sont discrètes : une résolution fetch, un clic.
 *   Faire tourner un RAF pour deux transitions par entité serait du gaspillage
 *   CPU pur. Le modèle event-driven est le bon outil pour ce cas d'usage.
 *
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ARB-5  format=json EXPLICITE
 *
 *   Le script original omettait &format=json dans l'URL oEmbed.
 *   Sans ce paramètre, le serveur peut retourner XML selon le contexte
 *   de la requête (Accept header). response.json() échouerait silencieusement.
 *   Corrigé : &format=json systématique.
 */

;(function YouTubeECS() {

  // ── 0. États de la machine ─────────────────────────────────────────────
  // Valeurs d'état pour dataStore[id].status. Voir ARB-1.

  const STATE = Object.freeze({
    PENDING : 'PENDING',
    READY   : 'READY',
    PLAYING : 'PLAYING',
    ERROR   : 'ERROR',
  })

  // ── 1. AOT Templates ──────────────────────────────────────────────────
  //  Parsing O(1) global. cloneNode(true) O(1) par instanciation (INV-2).
  //  Deux templates : vignette (état READY) et erreur (état ERROR).

  const _TPL_THUMB = document.createElement('template')
  _TPL_THUMB.innerHTML = `
    <div class="thumbnail-youtube">
      <button class="yt-play-btn" data-action="PLAY" aria-label="Lire la vidéo">
        <svg role="img" focusable="false">
          <use href="/sprites/util.svg#youtube"></use>
        </svg>
      </button>
      <div class="video-youtube-title"></div>
    </div>`

  const _TPL_ERROR = document.createElement('template')
  _TPL_ERROR.innerHTML = `
    <div class="thumbnail-youtube">
      <div class="video-youtube-error">
        Erreur : cette vidéo n'existe pas !<br>
        (ou a été supprimée...)<br>
        <svg role="img" focusable="false" class="icon scale" style="--scale:500%">
          <use href="/sprites/util.svg#space-invader"></use>
        </svg>
      </div>
    </div>`

  // ── 2. Stores ──────────────────────────────────────────────────────────
  //  dataStore  Données métier. Source de vérité (INV-5).
  //             Écrit par FetchSystem. Lu par UIRenderSystem et CommandSystem.
  //  domStore   Références DOM. Écrit à l'init. Jamais muté.

  const dataStore = {} // { id: string, title: string, thumbUrl: string,
                       //   embedUrl: string, status: STATE, _ac: AbortController }
  const domStore  = {} // { container: Element, thumbnail: Element|null }

  // ── 3. Command Buffer ──────────────────────────────────────────────────
  //  File FIFO. InputSystem y pousse les commandes utilisateur.
  //  CommandSystem la draine de manière synchrone à chaque flush().
  //  Structure : { entityId: number, type: string }

  const _commandBuffer = []

  const dispatch = (entityId, type) =>
    _commandBuffer.push({ entityId, type })

  // ── 4. CommandSystem ───────────────────────────────────────────────────
  //  Transitions d'état. Seul système à écrire dataStore.status.
  //  Appelé par _flushCommands() après chaque événement input.

  const _commands = {

    PLAY(entityId) {
      const data = dataStore[entityId]
      // Guard : transition PLAYING uniquement depuis READY.
      // Protège contre le double-clic et les commandes parasites.
      if (data?.status !== STATE.READY) return
      data.status = STATE.PLAYING
      UIRenderSystem.renderIframe(entityId)
    },
  }

  const _flushCommands = () => {
    const len = _commandBuffer.length
    for (let i = 0; i < len; i++) {
      const { entityId, type } = _commandBuffer[i]
      _commands[type]?.(entityId)
    }
    _commandBuffer.splice(0, len)
  }

  // ── 5. FetchSystem ─────────────────────────────────────────────────────
  //  Requête oEmbed par entité. Asynchrone et isolée par AbortController.
  //  À la résolution : écrit dataStore, déclenche le render de la vignette.
  //  En cas d'échec : transite vers ERROR, déclenche le render d'erreur.

  const FetchSystem = {
    fetch(entityId) {
      const data = dataStore[entityId]
      const url  = `https://youtube.com/oembed?url=https://www.youtube.com/watch?v=${data.id}&format=json`

      fetch(url, { signal: data._ac.signal })
        .then(response => {
          if (!response.ok) throw new Error(`HTTP ${response.status}`)
          return response.json()
        })
        .then(json => {
          data.title    = json.title
          data.thumbUrl = json.thumbnail_url
          data.status   = STATE.READY
          UIRenderSystem.renderThumb(entityId)
        })
        .catch(err => {
          // AbortError = dispose() appelé pendant le fetch : pas d'erreur UI.
          if (err.name === 'AbortError') return
          console.error(`[YouTubeECS] Fetch échoué pour l'entité ${entityId} (id: ${data.id})`, err)
          data.status = STATE.ERROR
          UIRenderSystem.renderError(entityId)
        })
    },
  }

  // ── 6. UIRenderSystem ──────────────────────────────────────────────────
  //  Seul système autorisé à modifier le DOM (INV-1).
  //  Trois renders discrets : vignette, iframe, erreur.
  //  Chaque render est déclenché une seule fois, lors d'une transition d'état.
  //  Toutes les données lues proviennent exclusivement de dataStore (INV-5).

  const UIRenderSystem = {

    // Render READY : clone AOT, injecte les données du store, monte dans le DOM.
    renderThumb(entityId) {
      const data      = dataStore[entityId]
      const container = domStore[entityId].container

      const node  = _TPL_THUMB.content.cloneNode(true)
      const wrap  = node.querySelector('.thumbnail-youtube')
      const btn   = node.querySelector('.yt-play-btn')
      const title = node.querySelector('.video-youtube-title')

      // Rattachement de l'entityId au player pour la résolution par InputSystem.
      wrap.dataset.entityId = entityId
      wrap.style.backgroundImage = `url(${data.thumbUrl})`
      title.textContent = data.title
      btn.setAttribute('aria-label', `Lire : ${data.title}`)

      container.appendChild(node)

      // Capture de la ref pour le retrait lors de la transition PLAYING.
      domStore[entityId].thumbnail = container.querySelector('.thumbnail-youtube')
    },

    // Render PLAYING : retire la vignette, injecte l'iframe.
    // Voir ARB-2 pour le choix de createElement direct.
    renderIframe(entityId) {
      const data = dataStore[entityId]
      const dom  = domStore[entityId]

      dom.thumbnail?.remove()
      dom.thumbnail = null

      const iframe = document.createElement('iframe')
      iframe.src   = `https://www.youtube.com/embed/${data.id}?feature=oembed&autoplay=1`
      iframe.title = data.title
      iframe.setAttribute('allowfullscreen', '')

      dom.container.appendChild(iframe)
      dom.iframe = iframe
    },

    // Render ERROR : clone AOT, monte dans le DOM.
    renderError(entityId) {
      const node = _TPL_ERROR.content.cloneNode(true)
      domStore[entityId].container.appendChild(node)
    },
  }

  // ── 7. InputSystem ─────────────────────────────────────────────────────
  //  Un seul listener click sur document (INV-3).
  //  Résolution : e.target → [data-action] → [data-entity-id] → dispatch().
  //  Signal AbortController global : invalidé par dispose() du module entier.

  const InputSystem = {
    _ac: null,

    init() {
      const ac = new AbortController()
      InputSystem._ac = ac
      document.addEventListener('click', InputSystem._route, { signal: ac.signal })
    },

    _route(e) {
      const btn = e.target.closest('[data-action]')
      if (!btn) return
      const wrap = btn.closest('[data-entity-id]')
      if (!wrap) return
      dispatch(+wrap.dataset.entityId, btn.dataset.action)
      _flushCommands()
    },

    dispose() { InputSystem._ac?.abort() },
  }

  // ── 8. dispose ─────────────────────────────────────────────────────────
  //  Nettoyage complet d'une entité.
  //  abort() annule le fetch en cours ET invalide le listener (ARB-3).
  //  Retrait du DOM avant purge des stores (même ordre que mediaPlayer.js).

  const disposeEntity = entityId => {
    dataStore[entityId]?._ac.abort()
    domStore[entityId]?.thumbnail?.remove()
    domStore[entityId]?.iframe?.remove()
    delete dataStore[entityId]
    delete domStore[entityId]
  }

  // ── 9. Compteur module-scope ───────────────────────────────────────────
  //  Survit à plusieurs appels bootstrap(). Garantit l'unicité des entityIds.

  let _nextEntityId = 0

  // ── 10. bootstrap ──────────────────────────────────────────────────────
  //  Point d'entrée public. container permet d'isoler le scope de découverte.
  //  Guard _mediaIndex-équivalent : dataset.ytEntityId évite la double-init
  //  du même élément DOM lors d'appels bootstrap() successifs (ex: AJAX).

  const bootstrap = (container = document) => {
    const elements = container.querySelectorAll('.video-youtube')

    for (const el of elements) {
      if (el.dataset.ytEntityId !== undefined) continue // guard idempotence
      const videoId  = el.dataset.id
      if (!videoId) continue

      const entityId = _nextEntityId++
      el.dataset.ytEntityId = entityId // sceau d'init sur l'élément source

      dataStore[entityId] = {
        id:       videoId,
        title:    '',
        thumbUrl: '',
        embedUrl: '',
        status:   STATE.PENDING,
        _ac:      new AbortController(),
      }
      domStore[entityId] = {
        container: el,
        thumbnail: null,
        iframe:    null,
      }

      FetchSystem.fetch(entityId)
    }

    // InputSystem.init() est idempotent via AbortController :
    // un second bootstrap() ne double pas le listener.
    if (!InputSystem._ac) InputSystem.init()
  }

  // Compatibilité chargement synchrone/asynchrone du script.
  document.readyState === 'loading'
    ? document.addEventListener('DOMContentLoaded', () => bootstrap(), { once: true })
    : bootstrap()

  // ── API publique ────────────────────────────────────────────────────────
  window.YouTubePlayer = {
    /** Initialise les players dans un sous-arbre (ex: après AJAX). */
    bootstrap,
    /** Commande impérative externe : YouTubePlayer.dispatch(0, 'PLAY') */
    dispatch(entityId, type) { dispatch(entityId, type); _flushCommands() },
    /** Nettoyage d'une entité par son ID. */
    dispose: disposeEntity,
    /** Accès en lecture aux stores (tests, intégration externe). */
    stores: { data: dataStore, dom: domStore },
  }

})()
