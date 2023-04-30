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
  <div class="media-time">
    <output class="media-current-time"aria-label="current time">0:00</output>&nbsp;/&nbsp;<output class="media-duration"aria-label="duration">0:00</output>
  </div>
  <input type="range" class="media-progress-bar" aria-label="progress bar" min="0" max="100" step="1" value="0">
  <div class="media-extend-volume" tabindex="0">
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
  const output = media.nextElementSibling.querySelector('.media-duration')
  media.readyState >= 1 ? output.value = secondsToTime(media.duration) : media.addEventListener('loadedmetadata', () => output.value = secondsToTime(media.duration))
}

const currentTime = (media, output, progressBar) => {
  setInterval(frame, 50)
  function frame() {
    output.value = secondsToTime(media.currentTime)
    progressBar.value = media.currentTime / media.duration * 100
    progressBar.style.setProperty('--position', `${Math.floor(media.currentTime / media.duration * 10000) / 100}%`) // @note Deux chiffres après la virgule.
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

const togglePictureInPicture = media => {
  // @see https://developer.mozilla.org/en-US/docs/Web/API/Picture-in-Picture_API
  if (document.pictureInPictureElement) document.exitPictureInPicture()
  else if (document.pictureInPictureEnabled) media.requestPictureInPicture()
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

const controls = media => {

  const player = media.nextElementSibling,
        playPauseButton = player.querySelector('.media-play-pause'),
        //time = player.querySelector('.media-time'),
        output = player.querySelector('.media-current-time'),
        progressBar = player.querySelector('.media-progress-bar'),
        extendVolume = player.querySelector('.media-extend-volume'),
        volumeBar = player.querySelector('.media-volume-bar'),
        muteButton = player.querySelector('.media-mute'),
        fullscreenButton = player.querySelector('.media-fullscreen'),
        menuButton = player.querySelector('.media-menu'),
        nextReadingButton = player.querySelector('.media-next-reading'),
        pictureInPictureButton = player.querySelector('.media-picture-in-picture'),
        leapRewindButton = player.querySelector('.media-leap-rewind'),
        leapForwardButton = player.querySelector('.media-leap-forward'),
        //fastRewindButton = player.querySelector('.media-fast-rewind'),
        //fastForwardButton = player.querySelector('.media-fast-forward'),
        stopButton = player.querySelector('.media-stop'),
        replayButton = player.querySelector('.media-replay')

const mediaRelationship = media.closest('.media-relationship'),
      nextMedia = '' //mediaRelationship.querySelectorAll('.media').forEach(m => (m !== e.target) && m.pause())

let playlistEnabled = false

  // Remove Controls :
  // @note Le code est plus simple et robuste si l'on se contente de supprimer des boutons déjà présents dans le player plutôt que de les ajouter (cibler leur place dans le DOM, rattacher les fonctionnalités...)

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

  // Contrôle via les événements :

  document.addEventListener('play', e => { // @note Si un lecteur actif sur la page, alors les autres se mettent en pause.
    medias.forEach(media => (media !== e.target) && media.pause())
    // Avec option '.media-single-player' dans un élément parent :
    //medias.forEach(media => (media.closest('.media-single-player') && media !== e.target) && media.pause())
  }, true)

  media.addEventListener('waiting', () => { // Si chargement de la ressource.
    player.classList.add('waiting')
  })
  
  media.addEventListener('canplay', () => { // @todo Si ressource disponible à la lecture.
    player.classList.remove('waiting')
  })

  ;['click', 'play', 'pause', 'ended', 'input'].forEach(event => {
    document.addEventListener(event, () => { // document.documentElement
      // @note Ne mettre ici que les boutons liés au player en cours.
      buttonState(!media.paused, playPauseButton)
      buttonState(media.muted || media.volume === 0, muteButton)
      buttonState(media.onplayed || media.paused && media.currentTime === 0, stopButton)
      buttonState(media.loop, replayButton)
      media.paused && media.currentTime === 0 ? stopButton.disabled = true : stopButton.disabled = false
    })
  })

  media.addEventListener('ended', () => {
    playPauseButton.classList.remove('active')
    media.currentTime = 0
    stopButton.classList.add('active')
    stopButton.disabled = true
    /*
    if (playlistEnabled) { // @todo En dev'...
      media = nextMedia
      media.currentTime = 0
      togglePlayPause(media)
    }
    */
  })

  media.addEventListener('pause', () => playPauseButton.classList.remove('active'))

  // Contrôle via les boutons :

  playPauseButton.addEventListener('click', () => {
    togglePlayPause(media)
    currentTime(media, output, progressBar)
    menu(player, false)
  })

  muteButton.addEventListener('click', () => mute(media))

  progressBar.addEventListener('input', e => {
    media.currentTime = (progressBar.value / progressBar.max) * media.duration
    currentTime(media, output, progressBar)
  })

  volumeBar.addEventListener('input', e => {
    const position = volumeBar.value / volumeBar.max
    media.volume = position
    volumeBar.style.setProperty('--position', `${position * 100}%`)
  })

  menuButton.addEventListener('click', () => { // @note Fonction de notre player, non liée à la source media.
    menuButton.classList.toggle('active')
    menu(player, true)
  })

  nextReadingButton.addEventListener('click', e => {
    playlistEnabled = !playlistEnabled
    mediaRelationship.querySelectorAll('.media').forEach(media => { // @note Il peut s'agir de n'importe quel media de la playlist.
      media.nextElementSibling.querySelector('.media-next-reading').classList.toggle('active')
      if (playlistEnabled) media.loop = false
    })
  })

  if (media.tagName === 'VIDEO' && document.fullscreenEnabled) {
    fullscreenButton.addEventListener('click', () => fullscreen(media))
  }

  pictureInPictureButton.addEventListener('click', () => {
    buttonState(!document.pictureInPictureElement, pictureInPictureButton) // @note Ne pas mettre avec les clics généraux car cette fonction est en lien avec tous les players, pas seulement le player actuel.
    togglePictureInPicture(media)
  })

  //fastRewindButton.addEventListener('click', () => fastRewind(media))

  //fastForwardButton.addEventListener('click', () => fastForward(media))

  leapRewindButton.addEventListener('click', () => {
    leapRewind(media)
    currentTime(media, output, progressBar)
  })

  leapForwardButton.addEventListener('click', () => {
    leapForward(media)
    currentTime(media, output, progressBar)
  })

  stopButton.addEventListener('click', () => {
    stop(media)
    currentTime(media, output, progressBar)
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
    player.classList.add('error')
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
      default: message = 'Reading error' // 'Erreur de lecture'
    }
    time.innerHTML = message //`<span>${message}</span>`
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
