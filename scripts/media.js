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
  media.addEventListener('loadedmetadata',() => output.value = secondsToTime(media.duration))
  output.value = secondsToTime(media.duration)
}

const currentTime = () => {
  for (const media of medias) {
    const player = media.nextElementSibling
    const output = player.querySelector('.media-current-time')
    const progress = player.querySelector('.media-progress-bar')
    setInterval(frame, 100) // @todo A voir pour faire varier la valeur fixe selon la longeur du morceau : une grosse valeur est préjudiciable pour les petits fichiers MP3, la barre de progression saccade.
    function frame() {
      output.value = secondsToTime(media.currentTime)
      progress.value = media.currentTime / media.duration * 1000
      progress.style.setProperty('--stop', `${media.currentTime / media.duration * 100}%`)
    }
  }
}

/*
const currentTime = () => {
  for (const media of medias) {
    const player = media.nextElementSibling
    const output = player.querySelector('.media-current-time')
    const progress = player.querySelector('.media-progress-bar > div')
    setInterval(frame, 200)
    function frame() {
      output.value = secondsToTime(media.currentTime)
      let widthBar = media.currentTime / media.duration * 100
      progress.style.width = widthBar + '%'
    }
  }
}
*/

const togglePlayPause = media => media.paused ? media.play() : media.pause()

function mute(player) {
  const media = player.previousElementSibling
  media.volume === 0 ? media.volume = 1 : media.volume = 0
}

function buttonToggle(button) {
  if (button.classList.contains('active')) button.classList.remove('active')
  else button.classList.add('active')
}

function cmdInit(player) {
  const media = player.previousElementSibling
  const buttonPlayPause = player.querySelector('.media-play-pause')
  const buttonVolume = player.querySelector('.media-volume')

  buttonPlayPause.addEventListener('click', () => {
    togglePlayPause(media)
    buttonToggle(buttonPlayPause)
    currentTime()
  })

  buttonVolume.addEventListener('click', () => {
    mute(player)
    buttonToggle(buttonVolume)
  })
  player.previousElementSibling.addEventListener('ended', () => buttonToggle(buttonPlayPause)) // Si fin de la lecture.
}

addAudioPlayer()
document.querySelectorAll('.media-player').forEach(player => cmdInit(player))


document.addEventListener('play', e => { // Si un lecteur actif sur la page, alors les autres se mettent en pause.
  [...document.querySelectorAll('.media')].forEach((media) => { // audio, video
    if (media !== e.target) {
      media.pause()
      media.nextElementSibling.querySelector('.media-play-pause').classList.remove('active')
    }
  })
}, true)

// Fonction à développer :
//audio.loop = true
