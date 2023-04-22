'use strict'

// @see https://developer.mozilla.org/en-US/docs/Web/Guide/Audio_and_video_delivery/cross_browser_video_player
// @see https://developer.mozilla.org/fr/docs/Learn/HTML/Multimedia_and_embedding/Video_and_audio_content

const medias = document.querySelectorAll('.media') // audio, video
const playerHTML = `
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
    <input type="range" class="media-volume-bar" min="0" max="10" step="1" value="5">
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
  <button class="media-menu" aria-label="menu">
    <svg focusable="false">
      <use href="/sprites/player.svg#menu"></use>
    </svg>
  </button>
</div>
`

const addMediaPlayer = media => {
  media.insertAdjacentHTML('afterend', playerHTML)
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

/**
 * Dissociation des styles et de l'attribut 'value' de l'imput range.
 * Grâce à ce procédé l'input range peut suivre une lecture éventuellement en cours tout en permettant à l'utilisateur de voir son intrerraction avec la barre de progression.
 */
const progressBarStyles = (media, progressBar) => progressBar.style.setProperty('--position', `${Math.floor(media.currentTime / media.duration * 10000) / 100}%`) // @note Deux chiffres après la virgule.

const currentTime = media => {
  const player = media.nextElementSibling,
        output = player.querySelector('.media-current-time'),
        progressBar = player.querySelector('.media-progress-bar')
  setInterval(frame, 50)
  function frame() {
    output.value = secondsToTime(media.currentTime)
    progressBar.value = media.currentTime / media.duration * 100
    progressBarStyles(media, progressBar)
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

const menu = player => {
  player.querySelector('.media-extend-menu').classList.toggle('active')
  ;[...document.querySelectorAll('.media-player')].forEach((mp) => { // @note Si un menu ouvert, alors les menus des autres players sont fermés.
    if (mp !== player) {
      mp.querySelector('.media-menu').classList.remove('active')
      mp.querySelector('.media-extend-menu').classList.remove('active')
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
        progressBar = player.querySelector('.media-progress-bar')

  // Contrôle via les événements:

  media.addEventListener('error', () => { // @todo À revoir, fonctionne une fois sur 3, sans doute problème de détection au chargement de la page...
    player.setAttribute('inert', '')
    player.classList.add('error')
    time.innerHTML = 'Error !'
  }, true)

  document.documentElement.addEventListener('click', () => {
    buttonState(!media.paused, playPauseButton)
    buttonState(media.muted, muteButton)
    buttonState(media.paused && media.currentTime === 0, stopButton)
    buttonState(media.loop, replayButton)
  })

  media.addEventListener('ended', () => {
    playPauseButton.classList.remove('active')
    media.currentTime = 0
    stopButton.classList.add('active')
  })

  media.addEventListener('pause', () => playPauseButton.classList.remove('active'))

  // Contrôle via les boutons :

  playPauseButton.addEventListener('click', () => {
    togglePlayPause(media)
    currentTime(media)
  })

  // Si balise html 'video' et API plein écran activée dans le navigateur :
  if (media.tagName === 'VIDEO' && !document?.fullscreenEnabled) fullscreenButton.addEventListener('click', () => fullscreen(media))

  muteButton.addEventListener('click', () => mute(media))

  stopButton.addEventListener('click', () => {
    stop(media)
    progressBarStyles(media, progressBar)
  })

  ;['click', 'rangeinput', 'touchmove'].forEach((event) => { // @todo 'touchmove' ?
    progressBar.addEventListener(event, e => {
      const DOMRect = progressBar.getBoundingClientRect()
      const position = (e.pageX - DOMRect.left) / progressBar.offsetWidth
      media.currentTime = position * media.duration
      progressBarStyles(media, progressBar)
    })
  })

  replayButton.addEventListener('click', () => replay(media))

  //fastRewindButton.addEventListener('click', () => fastRewind(media))

  //fastForwardButton.addEventListener('click', () => fastForward(media))

  leapRewindButton.addEventListener('click', () => {
    leapRewind(media)
    progressBarStyles(media, progressBar)
  })

  leapForwardButton.addEventListener('click', () => {
    leapForward(media)
    progressBarStyles(media, progressBar)
  })

  menuButton.addEventListener('click', () => { // @note Fonction de notre player, non liée à la source media.
    menuButton.classList.toggle('active')
    menu(player)
  })

}

document.addEventListener('play', e => { // Si un lecteur actif sur la page, alors les autres se mettent en pause.
  medias.forEach((media) => { // audio, video
    if (media !== e.target) media.pause()
  })
}, true)

let i = 0

for (const media of medias) {
  i++
  media.id = 'media-player' + i
  addMediaPlayer(media)
  media.removeAttribute('controls') // @note C'est bien Javascript qui doit se charger de cette opération, CSS ne doit pas le faire, ce qui permet un lecteur par défaut avec l'attribut "controls" si JS désactivé.
  controls(media)
}
