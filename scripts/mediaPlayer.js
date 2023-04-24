'use strict'

// @see https://developer.mozilla.org/en-US/docs/Web/Guide/Audio_and_video_delivery/cross_browser_video_player
// @see https://developer.mozilla.org/fr/docs/Learn/HTML/Multimedia_and_embedding/Video_and_audio_content

const medias = document.querySelectorAll('.media') // audio, video
const templateString = `
<div class="media-player">
  <button class="media-play-pause">
    <svg focusable="false">
      <use href="/sprites/player.svg#play"></use>
    </svg>
    <svg focusable="false">
      <use href="/sprites/player.svg#pause"></use>
    </svg>
  </button>
  <div class="media-time">
    <output class="media-current-time">0:00</output>&nbsp;/&nbsp;<output class="media-duration">0:00</output>
  </div>
  <input type="range" class="media-progress-bar" min="0" max="100" step="1" value="0">
  <div class="media-extended-volume" tabindex="0">
    <input type="range" class="media-volume-bar" min="0" max="1" step=".1" value=".5">
    <button class="media-mute" aria-label="play/pause">
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

const minmax = (number, min, max) => Math.min(Math.max(Number(number), min), max)

const addPlayer = media => {
  media.insertAdjacentHTML('afterend', templateString)
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

const buttonState = (mediaStatus, button) => mediaStatus ? button.classList.add('active') : button.classList.remove('active')

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

/**
 * Description :
 * 1. le menu s'ouvre et se ferme via le bouton ".media-menu",
 * 2. on peut ouvrir aussi les menus des autres players pendant la lecture en cours d'un autre player,
 * 3. le menu d'un player se referme si clic sur ".media-play-pause" d'un nouveau player.
 * @param {html} player
 * @param {boolean} menuButton
 */
const menu = (player, menuButton) => {
  menuButton || false
  const extendMenu = player.querySelector('.media-extend-menu')
  if (menuButton) extendMenu.classList.toggle('active')
  ;[...document.querySelectorAll('.media-player')].forEach((players) => {
    if (players !== player) { // @note Si un menu ouvert, alors les menus des autres players sont fermés.
      players.querySelector('.media-menu').classList.remove('active')
      players.querySelector('.media-extend-menu').classList.remove('active')
    }
  })
}

const controls = media => {

  const player = media.nextElementSibling,
        playPauseButton = player.querySelector('.media-play-pause'),
        fullscreenButton = player.querySelector('.media-fullscreen'),
        muteButton = player.querySelector('.media-mute'),
        stopButton = player.querySelector('.media-stop'),
        replayButton = player.querySelector('.media-replay'),
        //fastRewindButton = player.querySelector('.media-fast-rewind'),
        //fastForwardButton = player.querySelector('.media-fast-forward'),
        leapRewindButton = player.querySelector('.media-leap-rewind'),
        leapForwardButton = player.querySelector('.media-leap-forward'),
        menuButton = player.querySelector('.media-menu'),
        time = player.querySelector('.media-time'),
        output = player.querySelector('.media-current-time'),
        progressBar = player.querySelector('.media-progress-bar'),
        volumeBar = player.querySelector('.media-volume-bar')

  // Inialisation de valeurs :
  
  const init = (() => {
    //volumeBar.value = '.5'
    volumeBar.style.setProperty('--position', '50%')
    //progressBar.value = '.5'
    progressBar.style.setProperty('--position', '0%')
  })()

  // Contrôle via les événements :

  document.documentElement.addEventListener('click', () => {
    buttonState(!media.paused, playPauseButton)
    buttonState(media.muted || media.volume === 0, muteButton)
    buttonState(media.paused && media.currentTime === 0, stopButton)
    media.paused && media.currentTime === 0 ? stopButton.disabled = true : stopButton.disabled = false
    buttonState(media.loop, replayButton)
  })

  media.addEventListener('ended', () => {
    playPauseButton.classList.remove('active')
    media.currentTime = 0
    stopButton.classList.add('active')
    stopButton.disabled = true
  })

  media.addEventListener('pause', () => playPauseButton.classList.remove('active'))

  // Contrôle via les boutons :

  playPauseButton.addEventListener('click', () => {
    togglePlayPause(media)
    currentTime(media, output, progressBar)
    menu(player, false)
  })

  // Si balise 'video' et mode plein écran activé :
  if (media.tagName === 'VIDEO' && document.fullscreenEnabled) fullscreenButton.addEventListener('click', () => fullscreen(media))

  muteButton.addEventListener('click', () => mute(media))

  stopButton.addEventListener('click', () => {
    stop(media)
    currentTime(media, output, progressBar)
  })

  ;["pointerdown", "pointerup"].forEach((event) => { // 'touchmove', 'input' @todo Tous les types d'événements sont à évaluer.
    progressBar.addEventListener(event, e => {
      const DOMRect = progressBar.getBoundingClientRect()
      const position = (e.pageX - DOMRect.left) / progressBar.offsetWidth
      media.currentTime = position * media.duration
      currentTime(media, output, progressBar)
    })
  })

  ;['click', 'touchmove'].forEach((event) => {
    volumeBar.addEventListener(event, e => {
      const DOMRect = volumeBar.getBoundingClientRect()
      const position = minmax(Math.floor((e.pageX - DOMRect.left) / volumeBar.offsetWidth * 10) / 10, 0, 1)
      volumeBar.value = position
      media.volume = position
      console.log(  )
      volumeBar.style.setProperty('--position', `${position * 100}%`) // @note Deux chiffres après la virgule.
    })
  })

  replayButton.addEventListener('click', () => {
    replay(media)
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

  menuButton.addEventListener('click', () => { // @note Fonction de notre player, non liée à la source media.
    menuButton.classList.toggle('active')
    menu(player, true)
  })

}

document.addEventListener('play', e => { // Si un lecteur actif sur la page, alors les autres se mettent en pause.
  medias.forEach((media) => { // audio, video
    if (media !== e.target) media.pause()
  })
}, true)

const error = media => {
  // @note Afin de rendre possible la lecture des erreurs via un gestionnaire dévénement, on lit la source présente dans le HTML puis on la réaffecte via JS.
  // @see https://forum.alsacreations.com/topic-5-90423-1-Resolu-Lecteur-audiovideo-HTMLMediaElement--gestion-des-erreurs.html#lastofpage
  const srcHTML = media.currentSrc,
        player = media.nextElementSibling,
        time = player.querySelector('.media-time')

  media.src = srcHTML

  media.addEventListener('error', () => {
    player.setAttribute('inert', '')
    player.classList.add('error')
    //if (media.error.code === 1) time.innerHTML = 'Error: ressource loading aborted'
    //else if (media.error.code === 2) time.innerHTML = 'Error: no network'
    //else if (media.error.code === 3) time.innerHTML = 'Error: resource decoding failed'
    //else if (media.error.code === 4) time.innerHTML = 'Error: unsupported resource'
    //else time.innerHTML = 'Error'
    time.innerHTML = 'Erreur de lecture' //'Reading error'
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
