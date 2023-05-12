'use strict'

// @see https://developer.mozilla.org/en-US/docs/Web/Guide/Audio_and_video_delivery/cross_browser_video_player
// @see https://developer.mozilla.org/fr/docs/Learn/HTML/Multimedia_and_embedding/Video_and_audio_content

const medias = document.querySelectorAll('.media') // audio, video
const playerTemplate = `
<div class="media-player">
  <button class="media-play-pause" aria-label="play/pause">
    <svg focusable="false">
      <use href="/sprites/player.svg#play"></use>
    </svg>
    <svg focusable="false">
      <use href="/sprites/player.svg#pause"></use>
    </svg>
  </button>
  <div class="media-playback-rate">
    <output></output>
  </div>
  <div class="media-time">
    <output class="media-current-time"aria-label="current time">0:00</output>&nbsp;/&nbsp;<output class="media-duration"aria-label="duration">0:00</output>
  </div>
  <input type="range" class="media-progress-bar" aria-label="progress bar" min="0" max="100" step="1" value="0">
  <div class="media-extend-volume">
    <input type="range" class="media-volume-bar" aria-label="volume bar" min="0" max="1" step=".1" value=".5">
    <button class="media-mute" aria-label="mute">
      <svg focusable="false">
        <use href="/sprites/player.svg#volume-up"></use>
      </svg>
      <svg focusable="false">
        <use href="/sprites/player.svg#volume-off"></use>
      </svg>
    </button>
  </div>
  <button class="media-fullscreen" aria-label="fullscreen">
    <svg focusable="false">
      <use href="/sprites/player.svg#fullscreen"></use>
    </svg>
  </button>
  <button class="media-menu" aria-label="menu">
    <svg focusable="false">
      <use href="/sprites/player.svg#menu"></use>
    </svg>
  </button>
  <div class="media-extend-menu">
    <button class="media-next-reading" aria-label="next reading mode">
      <svg focusable="false">
        <use href="/sprites/player.svg#move-down"></use>
      </svg>
    </button>
    <button class="media-picture-in-picture" aria-label="picture in picture">
      <svg focusable="false">
        <use href="/sprites/player.svg#picture-in-picture"></use>
      </svg>
      <svg focusable="false">
        <use href="/sprites/player.svg#picture-in-picture-alt"></use>
      </svg>
    </button>
    <button class="media-slow-motion" aria-label="slow motion">
      <svg focusable="false">
        <use href="/sprites/player.svg#slow-motion-video"></use>
      </svg>
    </button>
    <button class="media-leap-rewind" aria-label="leap rewind">
      <svg focusable="false">
        <use href="/sprites/player.svg#rewind-10"></use>
      </svg>
    </button>
    <button class="media-leap-forward" aria-label="leap forward">
      <svg focusable="false">
        <use href="/sprites/player.svg#forward-10"></use>
      </svg>
    </button>
    <!--
    <button class="media-fast-rewind" aria-label="fast rewind">
      <svg focusable="false">
        <use href="/sprites/player.svg#fast-rewind"></use>
      </svg>
    </button>
    <button class="media-fast-forward" aria-label="fast forward">
      <svg focusable="false">
        <use href="/sprites/player.svg#fast-forward"></use>
      </svg>
    </button>
    -->
    <button class="media-stop" aria-label="stop">
      <svg focusable="false">
        <use href="/sprites/player.svg#stop"></use>
      </svg>
    </button>
    <button class="media-replay" aria-label="replay">
      <svg focusable="false">
        <use href="/sprites/player.svg#replay"></use>
      </svg>
    </button>
  </div>
</div>
`

//const minmax = (number, min, max) => Math.min(Math.max(Number(number), min), max)

const addPlayer = media => {
  media.insertAdjacentHTML('afterend', playerTemplate)
  mediaDuration(media)
}

const secondsToTime = seconds => { // @see https://stackoverflow.com/questions/3733227/javascript-seconds-to-minutes-and-seconds
  let hh = Math.floor(seconds / 3600).toString(),
      mm = Math.floor(seconds % 3600 / 60).toString(),
      ss = Math.floor(seconds % 60).toString().padStart(2, '0')
  if (hh === '0') hh = null // Si pas d'heures, alors info sur les heures escamotée.
  if (isNaN(hh)) hh = null // Si valeur nulle, alors info sur les heures escamotée.
  if (isNaN(mm)) mm = '0' // Si valeur nulle, alors affichage par défaut.
  if (isNaN(ss)) ss = '00' // Idem.
  return [hh, mm, ss].filter(Boolean).join(':')
}

const mediaDuration = media => {
  const player = media.nextElementSibling,
        time = player.querySelector('.media-time'),
        output = player.querySelector('.media-duration'),
        progressbar = player.querySelector('.media-progress-bar'),
        menu = player.querySelector('.media-menu'),
        extendMenu = player.querySelector('.media-extend-menu')
  media.readyState >= 1 ? output.value = secondsToTime(media.duration) : media.addEventListener('loadedmetadata', () => output.value = secondsToTime(media.duration))
  
  ;['loadeddata', 'loadedmetadata', 'click', 'play'].forEach(event => {
    media.addEventListener(event, () => {
      if (media.duration === Infinity) {
        time.innerHTML = 'Lecture en continu' // @todo À évaluer
        time.style.marginRight = 'auto'
        progressbar.remove()
        menu.remove()
        extendMenu.remove()
      }
    })
  })
  /*
  // @see https://stackoverflow.com/questions/65009249/mp3-files-duration-infinity-in-desktop-ios-safari
  const blob = await fetch(media.src
    )
    .then( (resp) => resp.blob() )
  if (media.duration === Infinity) {
    media.duration = 0
    time.innerHTML = 'Lecture en continu' // @todo À évaluer
    time.style.marginRight = 'auto'
    progressbar.remove()
    menu.remove()
    extendMenu.remove()
  }
  */
}

const currentTime = (media, output, progressBar) => {
  setInterval(frame, 50)
  function frame() {
    const ratio = Math.floor(media.currentTime / media.duration * 100) // @note Deux chiffres après la virgule.
    output.value = secondsToTime(media.currentTime)
    progressBar.value = ratio
    progressBar.style.setProperty('--position', `${ratio}%`)
  }
}

const buttonState = (status, button) => status ? button.classList.add('active') : button.classList.remove('active')

const togglePlayPause = media => media.paused ? media.play() : media.pause()

const fullscreen = media => media.requestFullscreen()

const mute = media => media.muted = !media.muted

const stop = media => {
  media.pause()
  media.currentTime = 0
}

const replay = (media) => media.loop = !media.loop

//const fastRewind = media => {}

//const fastForward = media => {}

const leapRewind = media => media.currentTime -= 10

const leapForward = media => media.currentTime += 10

const togglePictureInPicture = media => { // @see https://developer.mozilla.org/en-US/docs/Web/API/Picture-in-Picture_API
  if (document.pictureInPictureElement) document.exitPictureInPicture()
  else if (document.pictureInPictureEnabled) media.requestPictureInPicture()
}

const playbackRateChange = (media, playbackRateOutput) => {
  //(media.playbackRate > .25) ? media.playbackRate -= .2 : media.playbackRate = 4 // @note Les valeurs ont besoin d'être déterminées précisément car les résultats des soustractions sont approximatifs.
  switch (media.playbackRate) { // @note Plage navigateur recommandée entre 0.25 et 4.0.
    case (1): media.playbackRate = .8
      break
    case (.8): media.playbackRate = .6
      break
    case (.6): media.playbackRate = .5
      break
    case (.5): media.playbackRate = .3
      break
    case (.3): media.playbackRate = .2
      break
    case (.2): media.playbackRate = .1
      break
    case (.1): media.playbackRate = 4
      break
    case (4): media.playbackRate = 3
      break
    case (3): media.playbackRate = 2
      break
    case (2): media.playbackRate = 1.5
      break
    default: media.playbackRate = 1
  }
  playbackRateOutput.innerHTML = `x${Math.floor(media.playbackRate * 10) / 10}`
}

/**
 * Description :
 * 1. le menu s'ouvre et se ferme via le bouton ".media-menu",
 * 2. on peut ouvrir aussi les menus des autres players pendant la lecture en cours d'un autre player,
 * 3. le menu d'un player se referme si clic sur ".media-play-pause" d'un nouveau player.
 * @param {html} player
 * @param {boolean} menuButton
 */
const menu = (player, menuButton = false) => {
  const extendMenu = player.querySelector('.media-extend-menu')
  if (menuButton) extendMenu.classList.toggle('active')
  document.querySelectorAll('.media-player').forEach(players => {
    if (players !== player) { // @note Si un menu ouvert, alors les menus des autres players sont fermés.
      players.querySelector('.media-menu').classList.remove('active')
      players.querySelector('.media-extend-menu').classList.remove('active')
    }
  })
}

const nextMediaActive = (media, mediaRelationship) => {
  const relatedMedias = mediaRelationship.querySelectorAll('.media:not(.error)'),
        nextMedia = relatedMedias[[...relatedMedias].indexOf(media) + 1] || relatedMedias[0]

  media = nextMedia
  //media.currentTime = 0 // @note Désactivée : un utilisateur peut ainsi caler la plage suivante selon sa préférence personnelle.

  const player = media.nextElementSibling,
        playPauseButton = player.querySelector('.media-play-pause'),
        currentTimeOutput = player.querySelector('.media-current-time'),
        progressBar = player.querySelector('.media-progress-bar')

  togglePlayPause(media)
  buttonState(!media.paused, playPauseButton)
  currentTime(media, currentTimeOutput, progressBar)
}

const controls = (media) => {

  const player = media.nextElementSibling,
        playPauseButton = player.querySelector('.media-play-pause'),
        playbackRate = player.querySelector('.media-playback-rate'),
        playbackRateOutput = player.querySelector('.media-playback-rate *'),
        //time = player.querySelector('.media-time'),
        currentTimeOutput = player.querySelector('.media-current-time'),
        progressBar = player.querySelector('.media-progress-bar'),
        extendVolume = player.querySelector('.media-extend-volume'),
        volumeBar = player.querySelector('.media-volume-bar'),
        muteButton = player.querySelector('.media-mute'),
        fullscreenButton = player.querySelector('.media-fullscreen'),
        menuButton = player.querySelector('.media-menu'),
        nextReadingButton = player.querySelector('.media-next-reading'),
        pictureInPictureButton = player.querySelector('.media-picture-in-picture'),
        slowMotionButton = player.querySelector('.media-slow-motion'),
        leapRewindButton = player.querySelector('.media-leap-rewind'),
        leapForwardButton = player.querySelector('.media-leap-forward'),
        //fastRewindButton = player.querySelector('.media-fast-rewind'),
        //fastForwardButton = player.querySelector('.media-fast-forward'),
        stopButton = player.querySelector('.media-stop'),
        replayButton = player.querySelector('.media-replay'),
        mediaRelationship = media.closest('.media-relationship')

  // Remove Controls :
  // @note Le code est plus simple et robuste si l'on se contente de supprimer des boutons déjà présents dans le player plutôt que de les ajouter (cibler leur place dans le DOM qui peut changer au cours du développement, rattacher les fonctionnalités au DOM...)

  if (media.tagName === 'AUDIO' || !document.fullscreenEnabled) fullscreenButton.remove()
  if (media.tagName === 'AUDIO' || !document.pictureInPictureEnabled) pictureInPictureButton.remove()
  if (!mediaRelationship) nextReadingButton.remove()

  // Initialisation de valeurs :
  
  const initValues = (() => {
    progressBar.value = '0' // Valeur définie aussi dans le template string.
    volumeBar.value = '.5'
    progressBar.style.setProperty('--position', '0%')
    volumeBar.style.setProperty('--position', '50%')
  })()

  if (mediaRelationship) media.addEventListener('canplay', () => buttonState(mediaRelationship.getAttribute('data-next-reading') === 'true', media.nextElementSibling.querySelector('.media-next-reading')))

  // Contrôle via les événements :

  media.addEventListener('waiting', () => player.classList.add('waiting')) // Si ressource en cours de chargement.
  
  media.addEventListener('canplay', () => player.classList.remove('waiting')) // Si ressource chargée.

  document.addEventListener('play', e => { // @note Si un lecteur actif, alors les autres se mettent en pause.
    medias.forEach(media => (media !== e.target) && media.pause())
    // Avec option '.media-single-player' dans un élément parent :
    //medias.forEach(media => (media.closest('.media-single-player') && media !== e.target) && media.pause())
  }, true)

  ;['click', 'play', 'pause', 'ended', 'input'].forEach(event => {
    document.addEventListener(event, () => { // document.documentElement
      // @note Ne mettre ici que les boutons liés au player en cours.
      buttonState(!media.paused, playPauseButton)
      buttonState(media.muted || media.volume === 0, muteButton)
      //if (media.volume !== 0) muteButton.classList.remove('active')
      buttonState(media.onplayed || media.paused && media.currentTime === 0, stopButton)
      buttonState(media.loop, replayButton)
      media.paused && media.currentTime === 0 ? stopButton.disabled = true : stopButton.disabled = false
      // @note Variable CSS pilotée par JS ; permet de reprendre l'animation là où elle s'est arrêtée :
      //media.paused && playPauseButton.style.setProperty('--play-state', running === 'running' ? 'paused' : 'running')
    })
  })

  media.addEventListener('ended', () => {
    //media.currentTime = 0 // @note Permet de réénitialiser la lecture, mais le fait de s'abstenir de réinitialiser permet de mieux repérer les fichiers déjà lus.
    if (mediaRelationship.getAttribute('data-next-reading') === 'true') nextMediaActive(media, mediaRelationship)
    playPauseButton.classList.remove('active')
    stopButton.classList.add('active')
    stopButton.disabled = true
  })

  media.addEventListener('pause', () => playPauseButton.classList.remove('active'))

  // Contrôle via les boutons :

  playPauseButton.addEventListener('click', () => {
    togglePlayPause(media)
    currentTime(media, currentTimeOutput, progressBar)
    menu(player, false)
  })

  muteButton.addEventListener('click', () => mute(media))

  progressBar.addEventListener('input', () => {
    media.currentTime = (progressBar.value / progressBar.max) * media.duration
    currentTime(media, currentTimeOutput, progressBar)
  })

  volumeBar.addEventListener('input', () => {
    const position = volumeBar.value / volumeBar.max
    media.volume = position
    volumeBar.style.setProperty('--position', `${position * 100}%`)
  })

  menuButton.addEventListener('click', () => { // @note Fonction de notre player, non liée à la source media.
    menu(player, true)
    menuButton.classList.toggle('active')
  })

  nextReadingButton.addEventListener('click', () => {
    mediaRelationship.getAttribute('data-next-reading') === 'false' ? mediaRelationship.setAttribute('data-next-reading', 'true') : mediaRelationship.setAttribute('data-next-reading', 'false')
    mediaRelationship.querySelectorAll('.media').forEach(media => { // @note Il peut s'agir de n'importe lequel des medias du groupe en relation.
      if (mediaRelationship.getAttribute('data-next-reading') === 'true') media.loop = false
      buttonState(mediaRelationship.getAttribute('data-next-reading') === 'true', media.nextElementSibling.querySelector('.media-next-reading'))
    })
  })

  if (media.tagName === 'VIDEO' && document.fullscreenEnabled) {
    fullscreenButton.addEventListener('click', () => fullscreen(media))
  }

  pictureInPictureButton.addEventListener('click', () => {
    togglePictureInPicture(media)
    buttonState(!document.pictureInPictureElement, pictureInPictureButton) // @note Ne pas mettre avec les clics généraux car cette fonction est en lien avec tous les players, pas seulement le player actuel.
  })

  slowMotionButton.addEventListener('click', () => {
    playbackRateChange(media, playbackRateOutput)
    buttonState(media.playbackRate !== 1, slowMotionButton) // @note Toujours placé après la fonction playbackRateChange()
    if (media.playbackRate !== 1) playbackRate.classList.add('active') // @note Une fois activé on laisse l'affichage, même si retour à la valeur d'origine.
  })

  //fastRewindButton.addEventListener('click', () => fastRewind(media))

  //fastForwardButton.addEventListener('click', () => fastForward(media))

  leapRewindButton.addEventListener('click', () => {
    leapRewind(media)
    currentTime(media, currentTimeOutput, progressBar)
  })

  leapForwardButton.addEventListener('click', () => {
    leapForward(media)
    currentTime(media, currentTimeOutput, progressBar)
  })

  stopButton.addEventListener('click', () => {
    stop(media)
    currentTime(media, currentTimeOutput, progressBar)
  })

  replayButton.addEventListener('click', () => {
    replay(media)
  })

}

const error = media => {

  const player = media.nextElementSibling,
        time = player.querySelector('.media-time')

  media.src = media.currentSrc // @note Afin de rendre possible la lecture des erreurs via un gestionnaire d'événement, on lit la source présente dans le HTML puis on la réaffecte via JS. @see https://forum.alsacreations.com/topic-5-90423-1-Resolu-Lecteur-audiovideo-HTMLMediaElement--gestion-des-erreurs.html#lastofpage

  media.addEventListener('error', () => {
    player.setAttribute('inert', '')
    player.querySelectorAll('button, input').forEach(e => e.disabled = true) // @note Pour les anciens navigateurs.
    media.classList.add('error')
    player.classList.add('error')
    /*
    let message = ''
    switch (media.error.code) {
      case (1): message = 'Error: ressource loading aborted'
        break
      case (2): message = 'Error: no network'
        break
      case (3): message = 'Error: resource decoding failed'
        break
      case (4): message = 'Error: unsupported resource'
        break
      default: message = 'Reading error'
    }
    time.innerHTML = message //`<span>${message}</span>`
    */
    time.innerHTML = 'Erreur de lecture'
  }, true)
}

let i = 0

for (const media of medias) {
  i++
  media.id = 'media-player' + i
  media.removeAttribute('controls') // @note C'est bien Javascript qui doit se charger de cette opération, CSS ne doit pas le faire, ce qui permet un lecteur par défaut avec l'attribut "controls" si JS désactivé.
  addPlayer(media)
  controls(media)
  error(media)
}
