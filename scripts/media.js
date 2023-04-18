'use strict'

const medias = document.querySelectorAll('.media') // audio, video
const audioPlayerHTML = `
<div class="media-player">
  <button class="media-play-pause">
    <svg focusable="false">
      <use href="/sprites/ui.svg#play"></use>
    </svg>
    <svg focusable="false">
      <use href="/sprites/ui.svg#pause"></use>
    </svg>
  </button>
  <div class="media-time">
    <output class="media-current-time">0:00</output>&nbsp;/&nbsp;<output class="media-duration">0:00</output>
  </div>
  <input type="range" class="media-progress-bar" min="0" max="1000" step="1" value="0">
  <button class="media-volume">
    <svg focusable="false">
      <use href="/sprites/ui.svg#volume-up"></use>
    </svg>
    <svg focusable="false">
      <use href="/sprites/ui.svg#volume-off"></use>
    </svg>
  </button>
  <input type="range" class="media-volume-bar" min="0" max="10" step="1" value="5">
  <div class="media-extend-menu">
    <button class="media-leap-rewind">
      <svg focusable="false">
        <use href="/sprites/ui.svg#rewind-10"></use>
      </svg>
    </button>
    <button class="media-leap-forward">
      <svg focusable="false">
        <use href="/sprites/ui.svg#forward-10"></use>
      </svg>
    </button>
    <!--
    <button class="media-fast-rewind">
      <svg focusable="false">
        <use href="/sprites/ui.svg#fast-rewind"></use>
      </svg>
    </button>
    <button class="media-fast-forward">
      <svg focusable="false">
        <use href="/sprites/ui.svg#fast-forward"></use>
      </svg>
    </button>
    -->
    <button class="media-stop">
      <svg focusable="false">
        <use href="/sprites/ui.svg#stop"></use>
      </svg>
    </button>
    <button class="media-replay">
      <svg focusable="false">
        <use href="/sprites/ui.svg#replay"></use>
      </svg>
    </button>
  </div>
  <button class="media-menu">
    <svg focusable="false">
      <use href="/sprites/ui.svg#menu"></use>
    </svg>
  </button>
</div>
`

medias.forEach(media => media.removeAttribute('controls')) // @note Pas nécessaire, mais c'est plus propre !

const addAudioPlayer = () => {
  let i = 0
  for (const media of medias) {
    i++
    media.id = 'media-player' + i
    media.insertAdjacentHTML('afterend', audioPlayerHTML)
    mediaDuration(media)
  }
}

const secondsToTime = e => { // @see https://stackoverflow.com/questions/3733227/javascript-seconds-to-minutes-and-seconds
  let hh = Math.floor(e / 3600).toString(),
      mm = Math.floor(e % 3600 / 60).toString(),
      ss = Math.floor(e % 60).toString().padStart(2, '0')
  if (hh === '0') hh = null // Si pas d'heures, alors info sur les heures escamotée.
  if (isNaN(hh)) hh = null // Si valeur nulle, alors info sur les heures escamotée.
  if (isNaN(mm)) mm = '0' // Si valeur nulle, alors affichage par défaut.
  if (isNaN(ss)) ss = '00' // Idem.
  return [hh, mm, ss].filter(Boolean).join(':')
}

const mediaDuration = (media) => {
  const output = media.nextElementSibling.querySelector('.media-duration')
  media.readyState >= 1 ? output.value = secondsToTime(media.duration) : media.addEventListener('loadedmetadata', () => output.value = secondsToTime(media.duration))
}

const currentTime = () => {
  for (const media of medias) {
    const player = media.nextElementSibling,
          output = player.querySelector('.media-current-time'),
          progress = player.querySelector('.media-progress-bar')
    setInterval(frame, 200)
    function frame() {
      const ratio = media.currentTime / media.duration
      output.value = secondsToTime(media.currentTime)
      progress.value = ratio * 1000
      progress.style.setProperty('--stop', `${ratio * 100}%`)
    }
  }
}

const togglePlayPause = media => media.paused ? media.play() : media.pause()

function toggleActiveClass(el) {
  el.classList.contains('active') ? el.classList.remove('active') : el.classList.add('active')
}

function mute(player) {
  const media = player.previousElementSibling
  media.volume === 0 ? media.volume = 1 : media.volume = 0
}

function menu(player) {
  const extendMenu = player.querySelector('.media-extend-menu')
  toggleActiveClass(extendMenu)
}

function stop(player) {
  const media = player.previousElementSibling
  media.pause()
  media.currentTime = 0
}

function replay(player) {
  const media = player.previousElementSibling
  const test = player.querySelector('.media-replay').classList.contains('active')
  test ? media.loop = true : media.loop = false
}
/*
function fastRewind(player) {
}

function fastForward(player) {
}
*/
function leapRewind(player) {
  const media = player.previousElementSibling
  media.currentTime -= 10
}

function leapForward(player) {
  const media = player.previousElementSibling
  media.currentTime += 10
}

function control(player) {

  const media = player.previousElementSibling,
        buttonPlayPause = player.querySelector('.media-play-pause'),
        buttonVolume = player.querySelector('.media-volume'),
        buttonMenu = player.querySelector('.media-menu'),
        buttonStop = player.querySelector('.media-stop'),
        buttonReplay = player.querySelector('.media-replay'),
        //buttonFastRewind = player.querySelector('.media-fast-rewind'),
        //buttonFastForward = player.querySelector('.media-fast-forward'),
        buttonLeapRewind = player.querySelector('.media-leap-rewind'),
        buttonLeapForward = player.querySelector('.media-leap-forward')

  buttonPlayPause.addEventListener('click', () => {
    togglePlayPause(media)
    toggleActiveClass(buttonPlayPause)
    currentTime()
  })

  buttonVolume.addEventListener('click', () => {
    toggleActiveClass(buttonVolume)
    mute(player)
  })

  buttonMenu.addEventListener('click', () => {
    toggleActiveClass(buttonMenu)
    menu(player)
  })

  buttonStop.addEventListener('click', () => {
    //toggleActiveClass(buttonStop)
    stop(player)
  })

  buttonReplay.addEventListener('click', () => {
    toggleActiveClass(buttonReplay)
    replay(player)
  })
  /*
  buttonFastRewind.addEventListener('click', () => {
    toggleActiveClass(buttonFastRewind)
    fastRewind(player)
  })

  buttonFastForward.addEventListener('click', () => {
    toggleActiveClass(buttonFastForward)
    fastForward(player)
  })
  */
  buttonLeapRewind.addEventListener('click', () => {
    //toggleActiveClass(buttonLeapRewind)
    leapRewind(player)
  })

  buttonLeapForward.addEventListener('click', () => {
    //toggleActiveClass(buttonLeapForward)
    leapForward(player)
  })

  media.addEventListener('ended', () => {
    buttonPlayPause.classList.remove('active')
    media.currentTime = 0
  })

  media.addEventListener('pause', () => {
    buttonPlayPause.classList.remove('active')
  })

}

addAudioPlayer()

document.querySelectorAll('.media-player').forEach(player => control(player))

document.addEventListener('play', e => { // Si un lecteur actif sur la page, alors les autres se mettent en pause.
  [...document.querySelectorAll('.media')].forEach((media) => { // audio, video
    if (media !== e.target) {
      media.pause()
      media.nextElementSibling.querySelector('.media-play-pause').classList.remove('active')
    }
  })
}, true)
