'use strict'

const medias = document.querySelectorAll('.audio')
const audioPlayerHTML = `
<div class="audio-player">
  <button class="audio-play-pause">
    <svg focusable="false">
      <use href="/sprites/util.svg#control-play"></use>
    </svg>
    <svg focusable="false">
      <use href="/sprites/util.svg#control-pause"></use>
    </svg>
  </button>
  <div>
    <output class="audio-player-current-time">0:00</output>&nbsp;/&nbsp;<output class="audio-player-duration">0:00</output>
  </div>
  <div class="audio-progress"><div></div></div>
  <button class="audio-volume">
    <svg focusable="false">
      <use href="/sprites/util.svg#volume-high"></use>
    </svg>
    <svg focusable="false">
      <use href="/sprites/util.svg#volume-xmark"></use>
    </svg>
  </button>
  <button class="audio-menu">
    <svg focusable="false">
      <use href="/sprites/util.svg#ellipsis-vertical"></use>
    </svg>
  </button>
</div>
`

medias.forEach(media => media.removeAttribute('controls')) // @note Pas nécessaire, mais c'est plus propre !

const addAudioPlayer = () => {
  let i = 0
  for (const media of medias) {
    i++
    media.id = 'audio-player' + i
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
  const output = media.nextElementSibling.querySelector('.audio-player-duration')
  media.addEventListener('loadedmetadata',() => output.value = secondsToTime(media.duration))
  output.value = secondsToTime(media.duration)
}

const currentTime = () => {
  for (const media of medias) {
    const player = media.nextElementSibling
    const output = player.querySelector('.audio-player-current-time')
    const progress = player.querySelector('.audio-progress > div')
    setInterval(frame, 200)
    function frame() {
      output.value = secondsToTime(media.currentTime)
      let widthBar = media.currentTime / media.duration * 100
      progress.style.width = widthBar + '%'
    }
  }
}

const togglePlayPause = media => media.paused ? media.play() : media.pause()

function mute(player) {
  const media = player.previousElementSibling
  media.volume === 0 ? media.volume = 1 : media.volume = 0
  //audio.loop = true
}

function buttonToggle(button) {
  if (button.classList.contains('active')) button.classList.remove('active')
  else button.classList.add('active')
}

function cmdInit(player) {
  const media = player.previousElementSibling
  const buttonPlayPause = player.querySelector('.audio-play-pause')
  const buttonVolume = player.querySelector('.audio-volume')

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
document.querySelectorAll('.audio-player').forEach(player => cmdInit(player))


document.addEventListener('play', e => { // Si un lecteur actif sur la page, alors les autres se mettent en pause.
  [...document.querySelectorAll('audio, video')].forEach((media) => {
    if (media !== e.target) {
      media.pause()
      media.nextElementSibling.querySelector('.audio-play-pause').classList.remove('active')
    }
  })
}, true)
