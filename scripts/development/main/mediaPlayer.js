'use strict'

/**
 * mediaPlayer.js — Architecture ECS/DOD
 * ─────────────────────────────────────────────────────────────────────────
 *
 * Pipeline déterministe par frame :
 *   Input → CommandBuffer → CommandSystem → [HTMLMediaElement]
 *   → TimeSystem → LogicSystem → UIRenderSystem
 *
 * ─────────────────────────────────────────────────────────────────────────
 * INVARIANTS STRUCTURELS
 * ─────────────────────────────────────────────────────────────────────────
 *
 * INV-1  DOM = buffer de sortie exclusif. UIRenderSystem est le seul
 *        système autorisé à écrire dans le DOM.
 *
 * INV-2  Une seule boucle RAF. Zéro setInterval.
 *        Le setInterval(frame, 50) original créait des intervalles orphelins
 *        superposés à chaque clic play/seek/leap — les frames s'accumulaient
 *        sans jamais être annulées.
 *
 * INV-3  CommandSystem draine en premier à chaque frame, avant toute
 *        lecture d'état hardware (TimeSystem). L'ordre garantit que l'état
 *        lu reflète les commandes appliquées dans le même cycle.
 *
 * INV-4  TimeSystem lit l'état hardware après application des commandes.
 *        La source de vérité pour l'état de lecture est HTMLMediaElement,
 *        pas les stores. Voir ARB-2.
 *
 * INV-5  LogicSystem = transformations pures sur stores. Zéro DOM.
 *        Zéro effet de bord. N'est exécuté que pour les entités dirty.
 *
 * INV-6  UIRenderSystem gaté doublement : intersecting (IntersectionObserver)
 *        + dirty (marqué par CommandSystem ou TimeSystem).
 *
 * INV-7  Toutes les refs DOM capturées à l'init dans domStore[id].
 *        Zéro querySelector à runtime.
 *
 * INV-8  AbortController par entité. dispose() garantit zéro fuite mémoire.
 *
 * ─────────────────────────────────────────────────────────────────────────
 * ARBITRAGES ET COMPROMIS (décisions non visibles dans le code)
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ARB-1  STORES : OBJETS PLATS vs TypedArrays
 *
 *   Option rejetée : Float32Array indexé par entityId pour currentTime,
 *   duration, volume, etc.
 *
 *   Raison du rejet :
 *     Les TypedArrays apportent un gain de débit mémoire (contiguïté cache,
 *     SIMD implicite) lorsque la boucle de traitement est elle-même le
 *     goulot — typiquement plusieurs milliers d'entités (moteur physique,
 *     système de particules). Ici, le goulot est la mutation DOM et l'API
 *     HTMLMediaElement, pas la lecture des flottants.
 *
 *     Avec ~50 players, un Float32Array introduit deux régressions sans
 *     bénéfice mesurable :
 *       a. Debug : playbackStates[12] ne dit rien sans table d'index.
 *          Un objet nommé est un tag de debug gratuit.
 *       b. Layout management : indices parallèles à synchroniser
 *          manuellement entre timeStore[id], statusStore[id], etc.
 *          Source d'erreurs sans valeur ajoutée à cette échelle.
 *
 *   Décision : objets plats { [entityId]: data }. L'architecture reste
 *   DOD — données séparées de la logique — sans surcoût de gestion
 *   d'indices parallèles. Migration vers TypedArrays triviale et localisée
 *   aux stores si le nombre de players dépasse O(100).
 *
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ARB-2  OWNERSHIP DE L'ÉTAT DE LECTURE : HTMLMediaElement vs stores internes
 *
 *   Option rejetée : isPaused[entityId] écrit directement par InputSystem
 *   comme buffer interne d'état.
 *
 *   Raison du rejet :
 *     HTMLMediaElement est une API impérative externe. Son état n'appartient
 *     pas à notre ECS — il appartient au navigateur. Écrire
 *     isPaused[id] = true ne met pas le media en pause ; il faut appeler
 *     media.pause(). Inversement, une pause déclenchée par le système
 *     (coupure réseau, perte de focus, autoplay policy) ne passera jamais
 *     par notre buffer, créant une divergence silencieuse entre l'état
 *     interne et l'état réel.
 *
 *   Décision : modèle Read-Back.
 *     InputSystem → CommandBuffer → CommandSystem → media.pause() [write]
 *     TimeSystem ← media.paused [read-back]
 *     Les stores ne font que refléter l'état hardware lu à chaque frame.
 *     La source de vérité reste toujours HTMLMediaElement.
 *
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ARB-3  COMMAND BUFFER : DRAIN PARTIEL vs DRAIN TOTAL
 *
 *   Option rejetée : drain total de _commandBuffer à chaque frame
 *   (_commandBuffer.length sans capture préalable).
 *
 *   Raison du rejet :
 *     Certains handlers émettent eux-mêmes des commandes pendant le drain
 *     (ex. _ADVANCE → dispatch(id, 'TOGGLE_PLAY')). Un drain total en
 *     itération live traiterait ces commandes dans le même frame, créant
 *     des effets de cascade potentiellement non déterministes.
 *
 *   Décision : capture de la longueur avant le drain.
 *     const len = _commandBuffer.length
 *     Les commandes émises pendant ce cycle atterrissent dans la queue
 *     mais sont traitées au frame suivant. Le pipeline reste déterministe :
 *     chaque frame ne traite que les commandes issues d'inputs ou d'events
 *     antérieurs à son déclenchement.
 *
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ARB-4  DIRTY FLAG : DOUBLE ORIGINE (TimeSystem + CommandSystem)
 *
 *   Le flag dirty est positionné par deux systèmes distincts :
 *     a. TimeSystem : si currentTime a progressé (lecture active).
 *     b. CommandSystem : pour les commandes qui changent un état visible
 *        sans faire progresser currentTime (seek, mute, stop, leap, replay).
 *
 *   Cette dualité est intentionnelle. Une entité en pause ne sera jamais
 *   marquée dirty par TimeSystem (currentTime stable). Mais un seek ou un
 *   mute sur une entité en pause doit quand même déclencher un render.
 *   Le CommandSystem est le seul à connaître l'intention de l'utilisateur ;
 *   il est donc le seul qualifié pour marquer dirty dans ce cas.
 *
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ARB-5  EXCEPTIONS DOM DANS CommandSystem (hors UIRenderSystem)
 *
 *   INV-1 est violé de manière documentée et délimitée par trois handlers.
 *   Chaque exception est justifiée par une contrainte mécanique spécifique :
 *
 *   a. SET_VOLUME → volumeBar.style.setProperty('--position', ...)
 *      La valeur du volume bar est un feedback synchrone d'input range.
 *      Elle n'a pas de READ hardware correspondant dans TimeSystem
 *      (HTMLMediaElement ne reporte pas la position du slider). La passer
 *      par le pipeline complet (store → LogicSystem → UIRenderSystem)
 *      nécessiterait un store dédié pour une seule propriété CSS dont la
 *      valeur est déjà disponible dans le payload de l'événement.
 *
 *   b. SLOW_MOTION → playbackRateOutput.textContent
 *      Le taux de lecture est affiché une seule fois par changement de
 *      vitesse (action ponctuelle, pas un état cyclique). Faire transiter
 *      la string formatée par LogicSystem/UIRenderSystem sur chaque frame
 *      serait un surcoût structurel disproportionné.
 *
 *   c. _STREAM_DETECTED / _ERROR → mutations structurelles du player
 *      Ces deux états sont des transformations irréversibles de la structure
 *      DOM du player (retrait de nœuds, attribut inert). Ils ne sont pas
 *      des états de rendu cycliques : ils n'ont pas à être rejoués par
 *      UIRenderSystem à chaque frame. Les passer par le pipeline de rendu
 *      introduirait une complexité de gestion d'état (flag "déjà appliqué")
 *      sans bénéfice.
 *
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ARB-6  ENGINE : FONCTION tick() vs OBJET World instancié
 *
 *   Option rejetée : un objet World avec état interne orchestrant les
 *   systèmes via des méthodes d'enregistrement (world.addSystem(...)).
 *
 *   Raison du rejet :
 *     La fonction tick() est déjà un Engine — elle ordonne les phases de
 *     manière déterministe. Un objet World par-dessus crée une indirection
 *     supplémentaire (lookup de méthode, dispatch de tableau de systèmes)
 *     pour un cas d'usage où l'ordre des systèmes est fixe et connu à la
 *     compilation.
 *     Un World dynamique est justifié lorsque les systèmes sont ajoutés ou
 *     retirés à runtime (ex. moteur de jeu avec scènes). Ici, les quatre
 *     systèmes sont invariants pour toute la durée de vie de la page.
 *
 *   Décision : Engine = module avec tick() et start()/stop(). L'ordre
 *   des systèmes est explicite dans le corps de tick(), lisible en une
 *   lecture linéaire sans indirection.
 *
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ARB-7  ADJACENCES : PRÉ-CALCUL vs RÉSOLUTION À RUNTIME
 *
 *   Option rejetée : getNextMedia() recalculant querySelectorAll + indexOf
 *   à chaque événement 'ended' (comportement de l'implémentation originale).
 *
 *   Raison du rejet :
 *     querySelectorAll est une opération de traversée DOM en O(n).
 *     indexOf sur un Array spread est O(n). Pour un groupe de 20 medias,
 *     l'événement 'ended' déclenchait deux scans complets du sous-arbre DOM.
 *
 *   Décision : _resolveAdjacencies() exécutée une seule fois après init
 *   globale. nextEntityId et nextNextEntityId sont des entiers stockés dans
 *   configStore. MediaStackSystem.advance() ne fait que des accès O(1)
 *   sur les stores.
 *
 *   Contrainte : si des medias sont ajoutés ou retirés dynamiquement du DOM
 *   après bootstrap(), _resolveAdjacencies() doit être rejouée manuellement.
 *   Ce cas n'est pas géré automatiquement — c'est un compromis assumé en
 *   faveur de la simplicité du pipeline nominal.
 */

;(function MediaPlayerECS() {

  // ── 0. AOT Template ───────────────────────────────────────────────────────
  //  Parsing HTML O(1) global. cloneNode(true) O(1) par instanciation.
  //  data-action = identifiant de commande. Résolution par InputSystem.

  const _TEMPLATE = document.createElement('template')
  _TEMPLATE.innerHTML = `
  <div class="media-player">
    <button class="media-play-pause" data-action="TOGGLE_PLAY" aria-label="play/pause">
      <svg focusable="false"><use href="/sprites/player.svg#play"></use></svg>
      <svg focusable="false"><use href="/sprites/player.svg#play-disabled"></use></svg>
      <svg focusable="false"><use href="/sprites/player.svg#pause"></use></svg>
    </button>
    <div class="media-tags">
      <output class="media-subtitle-langage"></output>
      <output class="media-playback-rate"></output>
    </div>
    <div class="media-time">
      <output class="media-current-time" aria-label="current time">0:00</output>
      &nbsp;/&nbsp;
      <output class="media-duration" aria-label="duration">0:00</output>
    </div>
    <input type="range" class="media-progress-bar" data-action="SEEK"
           aria-label="progress bar" min="0" max="100" step="1" value="0">
    <div class="media-extend-volume">
      <input type="range" class="media-volume-bar" data-action="SET_VOLUME"
             aria-label="volume bar" min="0" max="1" step=".1" value=".5">
      <button class="media-mute" data-action="MUTE" aria-label="mute">
        <svg focusable="false"><use href="/sprites/player.svg#volume-up"></use></svg>
        <svg focusable="false"><use href="/sprites/player.svg#volume-off"></use></svg>
      </button>
    </div>
    <button class="media-fullscreen" data-action="FULLSCREEN" aria-label="fullscreen">
      <svg focusable="false"><use href="/sprites/player.svg#fullscreen"></use></svg>
    </button>
    <button class="media-menu" data-action="MENU" aria-label="menu">
      <svg focusable="false"><use href="/sprites/player.svg#menu"></use></svg>
    </button>
    <div class="media-extend-menu">
      <button class="media-next-reading" data-action="NEXT_READING" aria-label="next reading mode">
        <svg focusable="false"><use href="/sprites/player.svg#move-down"></use></svg>
      </button>
      <button class="media-subtitles" data-action="SUBTITLES" aria-label="subtitles">
        <svg focusable="false"><use href="/sprites/player.svg#subtitles"></use></svg>
      </button>
      <button class="media-picture-in-picture" data-action="PIP" aria-label="picture in picture">
        <svg focusable="false"><use href="/sprites/player.svg#picture-in-picture"></use></svg>
        <svg focusable="false"><use href="/sprites/player.svg#picture-in-picture-alt"></use></svg>
      </button>
      <button class="media-slow-motion" data-action="SLOW_MOTION" aria-label="slow motion">
        <svg focusable="false"><use href="/sprites/player.svg#slow-motion"></use></svg>
      </button>
      <button class="media-leap-rewind" data-action="LEAP_REWIND" aria-label="leap rewind">
        <svg focusable="false"><use href="/sprites/player.svg#rewind-5"></use></svg>
      </button>
      <button class="media-leap-forward" data-action="LEAP_FORWARD" aria-label="leap forward">
        <svg focusable="false"><use href="/sprites/player.svg#forward-5"></use></svg>
      </button>
      <button class="media-stop" data-action="STOP" aria-label="stop">
        <svg focusable="false"><use href="/sprites/player.svg#stop"></use></svg>
      </button>
      <button class="media-replay" data-action="REPLAY" aria-label="replay">
        <svg focusable="false"><use href="/sprites/player.svg#replay"></use></svg>
      </button>
    </div>
  </div>`

  // ── 1. Constantes ─────────────────────────────────────────────────────────

  const MEDIA_SELECTOR = '.media'
  const PLAYBACK_RATES = Object.freeze([0.5, 0.25, 0.5, 1, 2, 4, 2, 1])

  // ── 2. Stores — Data Layout plat indexé par entityId (integer) ────────────
  //
  //  timeStore     Données brutes hardware. Écrit par TimeSystem uniquement.
  //  statusStore   État discret/binaire. Écrit par TimeSystem uniquement.
  //  configStore   Configuration stable. Écrit à l'init et par CommandSystem
  //                pour les mutations de config (subtitleIdx, playbackRateIdx).
  //  domStore      Références DOM. Écrit à l'init uniquement. Jamais muté.
  //  computedStore Données transformées par LogicSystem + flags de rendu.
  //                dirty et intersecting sont les seuls champs écrits
  //                hors LogicSystem (par CommandSystem et IntersectionObserver).

  const timeStore    = {} // { currentTime, duration, bufferedEnd }
  const statusStore  = {} // { paused, muted, volume, loop, playbackRate, waiting, error }
  const configStore  = {} // { isAudio, isStream, tracks, subtitleIdx, playbackRateIdx,
                          //   mediaRelationship, nextEntityId, nextNextEntityId, _ac }
  const domStore     = {} // { media, player, playPauseButton, progressBar, … }
  const computedStore = {} // { ratio, bufferRatio, timeStr, durationStr,
                           //   isPlaying, isMuted, isStopped, dirty, intersecting }

  // Index inverse : HTMLMediaElement → entityId
  // WeakMap : pas de rétention de référence, compatible avec GC.
  /** @type {WeakMap<HTMLMediaElement, number>} */
  const _mediaIndex = new WeakMap()

  // Compteur d'entités en scope module.
  // Survit à plusieurs appels bootstrap() (ex: chargement AJAX).
  // Garantit l'unicité des entityIds sur toute la durée de vie de la page.
  let _nextEntityId = 0

  // ── 3. Command Buffer ──────────────────────────────────────────────────────
  //  File FIFO. InputSystem et les event listeners natifs y poussent.
  //  CommandSystem la draine en début de frame.
  //  Structure de commande : { entityId: number, type: string, payload?: any }

  const _commandBuffer = []

  /** Pousse une commande dans la file. Seul point d'écriture dans le buffer. */
  const dispatch = (entityId, type, payload) =>
    _commandBuffer.push({ entityId, type, payload })

  // ── 4. Utilitaires purs ────────────────────────────────────────────────────

  const _toTime = s => {
    if (!isFinite(s) || s < 0) return '0:00'
    const hh = Math.floor(s / 3600)
    const mm = Math.floor((s % 3600) / 60).toString()
    const ss = Math.floor(s % 60).toString().padStart(2, '0')
    return hh > 0 ? `${hh}:${mm.padStart(2, '0')}:${ss}` : `${mm}:${ss}`
  }

  // Mutation de classe sans lecture préalable du classList (write-only).
  const _cls = (el, name, on) => { if (el) on ? el.classList.add(name) : el.classList.remove(name) }

  // Ferme les menus de toutes les entités sauf currentId.
  // Itère domStore, pas le DOM.
  const _closeOtherMenus = currentId => {
    for (const id in domStore) {
      const eid = +id
      if (eid === currentId) continue
      domStore[eid].extendMenu?.classList.remove('active')
      domStore[eid].menuButton?.classList.remove('active')
    }
  }

  // ── 5. CommandSystem ───────────────────────────────────────────────────────
  //  Unique point d'entrée vers HTMLMediaElement.
  //  Chaque handler : lit configStore/domStore, appelle l'API impérative,
  //  marque dirty si l'état visible a changé.
  //  Exceptions documentées au DOM :
  //    – SET_VOLUME écrit le CSS de la volume bar directement (feedback
  //      d'input synchrone ; la valeur n'est pas dans timeStore).
  //    – SLOW_MOTION écrit playbackRateOutput directement (état non cyclique,
  //      pas de READ hardware correspondant dans TimeSystem).
  //    – ERROR et _STREAM_DETECTED font des mutations DOM ponctuelles
  //      d'initialisation (ne transitent pas par le RAF).

  const _handlers = {

    TOGGLE_PLAY(id) {
      const m = domStore[id].media
      m.paused ? m.play() : m.pause()
      // Cross-player pause géré par le listener 'play' capture dans InputSystem.
      _closeOtherMenus(id)
      // Préchargement du suivant
      const nextId = configStore[id].nextEntityId
      if (nextId !== null) {
        const nm = domStore[nextId]?.media
        if (nm) nm.preload = 'auto'
      }
    },

    SEEK(id, payload) {
      const m = domStore[id].media
      if (!m.duration) return
      m.currentTime = (payload.value / payload.max) * m.duration
      computedStore[id].dirty = true
    },

    SET_VOLUME(id, payload) {
      const pos = parseFloat(payload.value) / parseFloat(payload.max)
      domStore[id].media.volume = pos
      // Exception documentée : CSS de la volume bar (voir en-tête §5).
      domStore[id].volumeBar.style.setProperty('--position', `${pos * 100}%`)
    },

    MUTE(id) {
      domStore[id].media.muted = !domStore[id].media.muted
      computedStore[id].dirty = true
    },

    STOP(id) {
      domStore[id].media.pause()
      domStore[id].media.currentTime = 0
      computedStore[id].dirty = true
    },

    REPLAY(id) {
      domStore[id].media.loop = !domStore[id].media.loop
      computedStore[id].dirty = true
    },

    LEAP_REWIND(id) {
      domStore[id].media.currentTime -= 5
      computedStore[id].dirty = true
    },

    LEAP_FORWARD(id) {
      domStore[id].media.currentTime += 5
      computedStore[id].dirty = true
    },

    SLOW_MOTION(id) {
      // Exception documentée : playbackRateOutput (voir en-tête §5).
      const cfg  = configStore[id]
      const rate = PLAYBACK_RATES[cfg.playbackRateIdx]
      domStore[id].media.playbackRate = rate
      const out = domStore[id].playbackRateOutput
      if (out) {
        out.textContent = `x${rate}`
        _cls(out, 'active', rate !== 1)
      }
      _cls(domStore[id].slowMotionButton, 'active', rate !== 1)
      cfg.playbackRateIdx = (cfg.playbackRateIdx + 1) % PLAYBACK_RATES.length
    },

    SUBTITLES(id) {
      const cfg    = configStore[id]
      const dom    = domStore[id]
      const tracks = cfg.tracks
      if (!tracks?.length) return
      if (cfg.subtitleIdx >= 0 && tracks[cfg.subtitleIdx])
        tracks[cfg.subtitleIdx].mode = 'disabled'
      const next = cfg.subtitleIdx + 1
      if (next < tracks.length) {
        tracks[next].mode = 'showing'
        dom.subtitleLangageOutput.value = `cc: ${tracks[next].language}`
        _cls(dom.subtitlesButton,       'active', true)
        _cls(dom.subtitleLangageOutput, 'active', true)
        cfg.subtitleIdx = next
      } else {
        cfg.subtitleIdx = -1
        dom.subtitleLangageOutput.value = ''
        _cls(dom.subtitlesButton,       'active', false)
        _cls(dom.subtitleLangageOutput, 'active', false)
      }
    },

    NEXT_READING(id) {
      const rel = configStore[id].mediaRelationship
      if (!rel) return
      const enabling = rel.dataset.nextReading !== 'true'
      rel.dataset.nextReading = enabling ? 'true' : 'false'
      for (const oid in configStore) {
        if (configStore[+oid].mediaRelationship !== rel) continue
        if (enabling) domStore[+oid].media.loop = false
        _cls(domStore[+oid].nextReadingButton, 'active', enabling)
      }
    },

    FULLSCREEN(id) {
      domStore[id].media.requestFullscreen?.()
    },

    PIP(id) {
      if (document.pictureInPictureElement) {
        document.exitPictureInPicture()
        _cls(domStore[id].pipButton, 'active', false)
      } else if (document.pictureInPictureEnabled) {
        domStore[id].media.requestPictureInPicture()
          .then(() => _cls(domStore[id].pipButton, 'active', true))
          .catch(() => {})
      }
    },

    MENU(id) {
      const dom = domStore[id]
      if (!dom.extendMenu) return
      dom.extendMenu.classList.toggle('active')
      dom.menuButton.classList.toggle('active')
      _closeOtherMenus(id)
    },

    // ── Commandes internes (émises par event listeners, pas par InputSystem) ─

    // Avancement playlist. Délégué à MediaStackSystem.
    _ADVANCE(id) {
      MediaStackSystem.advance(id)
    },

    // Flux infini détecté. Mutation DOM ponctuelle d'initialisation.
    // Exception documentée : DOM écrit hors UIRenderSystem car c'est une
    // transformation irréversible de la structure du player, pas un état cyclique.
    _STREAM_DETECTED(id) {
      configStore[id].isStream = true
      const dom    = domStore[id]
      const timeEl = dom.player.querySelector('.media-time')
      if (timeEl) {
        timeEl.textContent = 'Lecture en continu'
        timeEl.style.marginRight = 'auto'
      }
      dom.progressBar?.remove()
      dom.menuButton?.remove()
      dom.extendMenu?.remove()
    },

    // Erreur de lecture. Verrouillage du player.
    _ERROR(id) {
      statusStore[id].error = true
      const dom = domStore[id]
      dom.player.setAttribute('inert', '')
      dom.player.querySelectorAll('button, input').forEach(el => el.disabled = true)
      dom.media.classList.add('error')
      dom.player.classList.add('error')
      dom.player.querySelector('.media-time').textContent = 'Erreur de lecture'
      if ('poster' in dom.media) dom.media.poster = ''
    },
  }

  const CommandSystem = {
    run() {
      // Capture de la longueur avant drain : les commandes émises pendant
      // ce cycle (ex: _ADVANCE → TOGGLE_PLAY) sont traitées au frame suivant.
      const len = _commandBuffer.length
      for (let i = 0; i < len; i++) {
        const { entityId, type, payload } = _commandBuffer[i]
        _handlers[type]?.(entityId, payload)
      }
      _commandBuffer.splice(0, len)
    },
  }

  // ── 6. TimeSystem ──────────────────────────────────────────────────────────
  //  PHASE READ : lecture groupée des propriétés hardware.
  //  Seul système à lire HTMLMediaElement. Zéro DOM. Zéro écriture DOM.
  //  Marque dirty si currentTime a progressé (lecture active).

  const TimeSystem = {
    run() {
      for (const id in domStore) {
        const eid = +id
        const m   = domStore[eid].media
        const ts  = timeStore[eid]
        const ss  = statusStore[eid]

        const prevTime     = ts.currentTime
        const prevDuration = ts.duration
        const prevBuffered = ts.bufferedEnd

        ts.currentTime = m.currentTime
        // Conserver NaN tel quel : m.duration est NaN avant résolution des
        // métadonnées. Utiliser || 0 masquerait la transition NaN → valeur
        // réelle et empêcherait le dirty de se lever au bon moment.
        ts.duration    = m.duration
        ts.bufferedEnd = m.buffered.length > 0
          ? m.buffered.end(m.buffered.length - 1) : 0

        ss.paused       = m.paused
        ss.muted        = m.muted
        ss.volume       = m.volume
        ss.loop         = m.loop
        ss.playbackRate = m.playbackRate

        // Lever dirty si l'une des trois valeurs hardware a muté.
        // Couvre : lecture active (currentTime), résolution de métadonnées
        // en pause (duration : NaN → float), buffering en pause (bufferedEnd).
        // NaN !== NaN est true en JS : la première frame post-métadonnées
        // lève dirty systématiquement. Comportement intentionnel.
        if (
          ts.currentTime !== prevTime     ||
          ts.duration    !== prevDuration ||
          ts.bufferedEnd !== prevBuffered
        ) computedStore[eid].dirty = true
      }
    },
  }

  // ── 7. LogicSystem ─────────────────────────────────────────────────────────
  //  Transformations pures. Entrée : timeStore + statusStore.
  //  Sortie : computedStore. Zéro DOM. Zéro effet de bord.
  //  Court-circuit si !dirty : les entités en pause ne sont pas recalculées.

  const LogicSystem = {
    run() {
      for (const id in timeStore) {
        const eid = +id
        const cs  = computedStore[eid]
        if (!cs.dirty) continue

        const ts  = timeStore[eid]
        const ss  = statusStore[eid]
        const dur = ts.duration

        // dur > 0 est false si NaN ou 0 : les ratios restent à 0 tant que
        // les métadonnées ne sont pas résolues. Comportement correct.
        cs.ratio       = dur > 0 ? Math.floor((ts.currentTime / dur) * 1000) / 10 : 0
        cs.bufferRatio = dur > 0 ? Math.floor((ts.bufferedEnd  / dur) * 100)       : 0
        cs.timeStr     = _toTime(ts.currentTime)
        cs.durationStr = _toTime(dur)
        cs.isPlaying   = !ss.paused
        cs.isMuted     = ss.muted || ss.volume === 0
        cs.isStopped   = ss.paused && ts.currentTime === 0
      }
    },
  }

  // ── 8. UIRenderSystem ──────────────────────────────────────────────────────
  //  Seul système autorisé à écrire dans le DOM (INV-1).
  //  Consomme exclusivement computedStore.
  //  Double garde :
  //    intersecting → IntersectionObserver (viewport culling)
  //    dirty        → état changé depuis le dernier frame
  //  Acquitte dirty après WRITE pour éviter les re-renders inutiles.

  const UIRenderSystem = {
    run() {
      for (const id in computedStore) {
        const eid = +id
        const cs  = computedStore[eid]
        if (!cs.intersecting || !cs.dirty) continue

        const dom = domStore[eid]
        const ss  = statusStore[eid]

        if (!configStore[eid].isStream && dom.progressBar) {
          dom.progressBar.value = cs.ratio
          dom.progressBar.style.setProperty('--position',        `${cs.ratio}%`)
          dom.progressBar.style.setProperty('--position-buffer', `${cs.bufferRatio}%`)
        }

        dom.currentTimeOutput.value = cs.timeStr

        // Durée : écriture conditionnelle (résolue de façon asynchrone).
        if (dom.durationOutput.value !== cs.durationStr)
          dom.durationOutput.value = cs.durationStr

        _cls(dom.playPauseButton, 'active', cs.isPlaying)
        _cls(dom.muteButton,      'active', cs.isMuted)

        if (dom.stopButton) {
          _cls(dom.stopButton, 'active', cs.isStopped)
          dom.stopButton.disabled = cs.isStopped
        }

        if (dom.replayButton) _cls(dom.replayButton, 'active', ss.loop)

        cs.dirty = false // acquittement
      }
    },
  }

  // ── 9. MediaStackSystem ────────────────────────────────────────────────────
  //  Gestion de la file de lecture séquentielle.
  //  Travaille sur des entityIds. Zéro querySelector.

  const MediaStackSystem = {
    advance(id) {
      const cfg = configStore[id]
      if (!cfg.mediaRelationship) return
      if (cfg.mediaRelationship.dataset.nextReading !== 'true') return

      // Saute les entités en erreur de manière itérative (pas récursive).
      let candidateId = cfg.nextEntityId
      while (candidateId !== null && statusStore[candidateId]?.error) {
        candidateId = configStore[candidateId]?.nextEntityId ?? null
      }
      if (candidateId === null || candidateId === id) return

      domStore[candidateId].media.play()

      const nextNextId = configStore[candidateId]?.nextEntityId ?? null
      if (nextNextId !== null) {
        const m = domStore[nextNextId]?.media
        if (m) m.preload = 'auto'
      }
    },
  }

  // ── 10. IntersectionObserver ───────────────────────────────────────────────
  //  Met à jour computedStore[id].intersecting.
  //  Pas de command buffer ici : la mise à jour est immédiate et n'a
  //  aucun effet sur HTMLMediaElement.

  const _observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      const id = +entry.target.dataset.entityId
      if (computedStore[id]) computedStore[id].intersecting = entry.isIntersecting
    }
  }, { threshold: 0.1 })

  // ── 11. InputSystem ────────────────────────────────────────────────────────
  //  Deux listeners globaux (click, input) sur document.
  //  Résolution : element → [data-action] → [data-entity-id] → dispatch().
  //  Zéro logique métier. Zéro accès aux stores.

  const InputSystem = {
    _ac: null,

    init() {
      const ac = new AbortController()
      InputSystem._ac = ac
      const sig = ac.signal

      document.addEventListener('click', InputSystem._route, { signal: sig })
      document.addEventListener('input', InputSystem._route, { signal: sig })

      // Pause cross-player : source de vérité = événement 'play' natif.
      // Déclenché par TOGGLE_PLAY et par MediaStackSystem.advance().
      document.addEventListener('play', e => {
        const srcId = _mediaIndex.get(e.target)
        if (srcId === undefined) return
        for (const id in domStore) {
          const eid = +id
          if (eid !== srcId) domStore[eid].media.pause()
        }
      }, { signal: sig, capture: true })

      document.addEventListener('fullscreenchange', () => {
        const active = !!document.fullscreenElement
        for (const id in domStore) _cls(domStore[+id].fullscreenButton, 'active', active)
      }, { signal: sig })
    },

    _route(e) {
      const el = e.target.closest('[data-action]')
      if (!el) return
      const playerEl = el.closest('[data-entity-id]')
      if (!playerEl) return
      dispatch(
        +playerEl.dataset.entityId,
        el.dataset.action,
        e.target.type === 'range' ? { value: e.target.value, max: e.target.max } : undefined
      )
    },

    dispose() { InputSystem._ac?.abort() },
  }

  // ── 12. Engine ─────────────────────────────────────────────────────────────
  //  Orchestre l'ordre d'exécution déterministe. Zéro logique métier.
  //  L'ordre est la seule responsabilité de ce module.

  const Engine = {
    _rafId:   null,
    _running: false,

    tick() {
      CommandSystem.run()    // 1. Commandes → HTMLMediaElement
      TimeSystem.run()       // 2. READ hardware → stores bruts
      LogicSystem.run()      // 3. Stores bruts → computedStore
      UIRenderSystem.run()   // 4. computedStore → DOM
      Engine._rafId = requestAnimationFrame(Engine.tick)
    },

    start() {
      if (Engine._running) return
      Engine._running = true
      Engine._rafId = requestAnimationFrame(Engine.tick)
    },

    stop() {
      cancelAnimationFrame(Engine._rafId)
      Engine._running = false
    },
  }

  // ── 13. Initialisation d'une entité ────────────────────────────────────────

  const _initEntity = (media, entityId) => {

    // Clone AOT + injection dans le DOM
    const player = _TEMPLATE.content.cloneNode(true).querySelector('.media-player')
    player.dataset.entityId = entityId
    media.insertAdjacentElement('afterend', player)

    // Capture de toutes les refs DOM en une passe. Jamais rejouée.
    const q = sel => player.querySelector(sel)
    domStore[entityId] = {
      media,
      player,
      playPauseButton:       q('.media-play-pause'),
      playbackRateOutput:    q('.media-playback-rate'),
      subtitleLangageOutput: q('.media-subtitle-langage'),
      currentTimeOutput:     q('.media-current-time'),
      durationOutput:        q('.media-duration'),
      progressBar:           q('.media-progress-bar'),
      volumeBar:             q('.media-volume-bar'),
      muteButton:            q('.media-mute'),
      fullscreenButton:      q('.media-fullscreen'),
      menuButton:            q('.media-menu'),
      extendMenu:            q('.media-extend-menu'),
      nextReadingButton:     q('.media-next-reading'),
      subtitlesButton:       q('.media-subtitles'),
      pipButton:             q('.media-picture-in-picture'),
      slowMotionButton:      q('.media-slow-motion'),
      stopButton:            q('.media-stop'),
      replayButton:          q('.media-replay'),
    }

    // Stores initiaux
    timeStore[entityId] = { currentTime: 0, duration: NaN, bufferedEnd: 0 }

    statusStore[entityId] = {
      paused: true, muted: false, volume: 0.5, loop: false,
      playbackRate: 1, waiting: false, error: false,
    }

    const mediaRelationship = media.closest('.media-relationship')
    const ac = new AbortController()
    configStore[entityId] = {
      isAudio:           media.tagName === 'AUDIO',
      isStream:          false,
      tracks:            media.textTracks,
      subtitleIdx:       -1,
      playbackRateIdx:   0,
      mediaRelationship,
      nextEntityId:      null, // résolu après init globale dans _resolveAdjacencies
      nextNextEntityId:  null,
      _ac:               ac,
    }

    computedStore[entityId] = {
      ratio: 0, bufferRatio: 0,
      timeStr: '0:00', durationStr: '0:00',
      isPlaying: false, isMuted: false, isStopped: true,
      dirty: true,        // force une WRITE au premier tick
      intersecting: true, // IntersectionObserver précise ensuite
    }

    _mediaIndex.set(media, entityId)

    // ── Pruning des contrôles inapplicables ──────────────────────────────
    const dom = domStore[entityId]
    const isAudio = media.tagName === 'AUDIO'
    if (isAudio || !document.fullscreenEnabled)       dom.fullscreenButton?.remove()
    if (isAudio || !document.pictureInPictureEnabled) dom.pipButton?.remove()
    if (!media.textTracks[0]) dom.subtitlesButton?.remove()
    if (!mediaRelationship)   dom.nextReadingButton?.remove()

    // ── CSS initiaux (écriture unique, hors RAF) ──────────────────────────
    dom.progressBar.style.setProperty('--position',        '0%')
    dom.progressBar.style.setProperty('--position-buffer', '0%')
    dom.volumeBar.style.setProperty('--position',          '50%')

    // ── Event listeners per-entity (nettoyés par AbortController) ────────
    const sig = ac.signal

    // Durée initiale
    const _setDuration = () => {
      if (isFinite(media.duration)) computedStore[entityId].dirty = true
    }
    media.readyState >= 1
      ? _setDuration()
      : media.addEventListener('loadedmetadata', _setDuration, { signal: sig, once: true })

    // Live stream
    const _handleInfinity = () => {
      if (media.duration !== Infinity) return
      dispatch(entityId, '_STREAM_DETECTED')
      // Nettoyage : ces events n'ont plus de raison d'être.
      ;['loadeddata', 'loadedmetadata', 'play'].forEach(ev =>
        media.removeEventListener(ev, _handleInfinity)
      )
    }
    ;['loadeddata', 'loadedmetadata', 'play'].forEach(ev =>
      media.addEventListener(ev, _handleInfinity, { signal: sig })
    )

    media.addEventListener('waiting', () => {
      statusStore[entityId].waiting = true
      player.classList.add('waiting')
    }, { signal: sig })

    media.addEventListener('canplay', () => {
      statusStore[entityId].waiting = false
      player.classList.remove('waiting')
      if (mediaRelationship)
        _cls(dom.nextReadingButton, 'active',
          mediaRelationship.dataset.nextReading === 'true')
    }, { signal: sig })

    media.addEventListener('ended', () => {
      media.currentTime = 0
      computedStore[entityId].dirty = true
      dispatch(entityId, '_ADVANCE')
      const nn = configStore[entityId].nextNextEntityId
      if (nn !== null) { const m = domStore[nn]?.media; if (m) m.preload = 'auto' }
    }, { signal: sig })

    // Subtitles : synchronisation état initial (attribut HTML "default")
    if (dom.subtitlesButton) {
      for (const track of media.textTracks) {
        if (track.mode !== 'showing') continue
        _cls(dom.subtitlesButton,       'active', true)
        _cls(dom.subtitleLangageOutput, 'active', true)
        dom.subtitleLangageOutput.value = `cc: ${track.language}`
        break
      }
    }

    // Erreur
    // Réaffectation de currentSrc pour activer le gestionnaire d'erreur.
    // @see https://forum.alsacreations.com/topic-5-90423-1-Resolu-Lecteur-audiovideo-HTMLMediaElement--gestion-des-erreurs.html
    media.src = media.currentSrc
    media.addEventListener('error', () => dispatch(entityId, '_ERROR'),
      { signal: sig, capture: true })

    _observer.observe(player)
  }

  // ── 14. Résolution des adjacences cross-entités ────────────────────────────
  //  Exécutée après init de toutes les entités.
  //  Stocke les entityIds des médias adjacents dans configStore.
  //  Garantit que MediaStackSystem ne fait jamais de querySelector.

  const _resolveAdjacencies = () => {
    for (const id in configStore) {
      const eid = +id
      const rel = configStore[eid].mediaRelationship
      if (!rel) continue
      const siblings = [...rel.querySelectorAll(MEDIA_SELECTOR)]
      const idx      = siblings.indexOf(domStore[eid].media)
      const nextM    = siblings[idx + 1] ?? siblings[0] ?? null
      const nextNM   = siblings[idx + 2] ?? siblings[0] ?? null
      const nextId   = nextM  ? (_mediaIndex.get(nextM)  ?? null) : null
      const nextNId  = nextNM ? (_mediaIndex.get(nextNM) ?? null) : null
      configStore[eid].nextEntityId     = nextId  === eid ? null : nextId
      configStore[eid].nextNextEntityId = nextNId === eid ? null : nextNId
    }
  }

  // ── 15. dispose ────────────────────────────────────────────────────────────
  //  Nettoyage complet d'une entité. AbortController invalide tous les
  //  listeners per-entity en O(1). Suppression des entrées dans tous les stores.

  const disposeEntity = entityId => {
    configStore[entityId]?._ac.abort()
    _observer.unobserve(domStore[entityId]?.player)
    // Retrait du player du DOM avant purge des stores.
    // Évite les interfaces fantômes si l'élément media est conservé dans le DOM.
    // Le media original n'est pas retiré : il préexistait avant bootstrap().
    domStore[entityId]?.player.remove()
    _mediaIndex.delete(domStore[entityId]?.media)
    delete timeStore[entityId]
    delete statusStore[entityId]
    delete configStore[entityId]
    delete computedStore[entityId]
    delete domStore[entityId]
  }

  // ── 16. bootstrap ──────────────────────────────────────────────────────────
  //  Point d'entrée public.
  //  container : élément racine de la recherche (default: document).
  //  Permet d'isoler plusieurs instances sur une même page.

  const bootstrap = (container = document) => {
    const medias = container.querySelectorAll(MEDIA_SELECTOR)
    for (const media of medias) {
      // Guard idempotence : évite la double-instanciation du même objet JS.
      // Sémantique : protège contre le même élément HTMLMediaElement, pas
      // contre un nouvel élément inséré à la même position DOM (ex: AJAX
      // qui détruit et recrée l'élément — nouvel objet = nouvelle entité).
      if (_mediaIndex.has(media)) continue
      media.removeAttribute('controls')
      media.id = `media-${_nextEntityId}`
      _initEntity(media, _nextEntityId)
      _nextEntityId++
    }
    _resolveAdjacencies()
    InputSystem.init()
    Engine.start()
  }

  // Compatibilité chargement asynchrone (script en <head> ou defer)
  document.readyState === 'loading'
    ? document.addEventListener('DOMContentLoaded', () => bootstrap(), { once: true })
    : bootstrap()

  // ── API publique ───────────────────────────────────────────────────────────
  window.MediaPlayer = {
    /** Commande impérative externe : MediaPlayer.dispatch(0, 'TOGGLE_PLAY') */
    dispatch,
    /** Nettoyage d'une entité par son ID */
    dispose: disposeEntity,
    /** Accès en lecture aux stores (tests, intégration externe) */
    stores: { time: timeStore, status: statusStore, config: configStore, computed: computedStore },
  }

})()
