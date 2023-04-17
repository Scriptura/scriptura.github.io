'use strict'

const medias = document.querySelectorAll('.audio')

const audioPlayer = () => {

  const addAudioPlayer = (() => {
    const audioPlayer = `
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
      <div class="progress"></div>
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
    let i = 0
    for (const media of medias) {
      i++
      media.id = 'audio-player' + i
      media.insertAdjacentHTML('afterend', audioPlayer)
      const output = media.nextElementSibling.querySelector('.audio-player-duration')
      // @bugfixed Réapplication de la fonction pour qu'elle ait le temps d'appliquer la valeur à l'output qui, lui aussi, est généré en JavaScript.
      // @todo Trouver une solution asynchrone ?
      mediaDuration(media, output)
      setTimeout(() => mediaDuration(media, output), 200)
      setTimeout(() => mediaDuration(media, output), 1000)
    }
  })()

  /*
  const currentTime = (() => {
    const output = document.querySelectorAll('.audio-player-current-time')
    let i = 0
    for (const audio of audios) {
      const currentTime = audio.currentTime
      const currentTimeISO = secondsToTime(duration)
      const outputValue = () => {
        output[i].value = currentTime ? currentTimeISO : '0:00'
      }
      i++
    }
  })()
  */

}

const secondsToTime = e => { // @see https://stackoverflow.com/questions/3733227/javascript-seconds-to-minutes-and-seconds
  let hh = Math.floor(e / 3600).toString().padStart(2, '0'),
      mm = Math.floor(e % 3600 / 60).toString().padStart(2, '0'),
      ss = Math.floor(e % 60).toString().padStart(2, '0')
  if (hh == '00') hh = null // Si pas d'heures, alors info sur les heures escamotée.
  if (isNaN(hh)) hh = null // Si valeur nulle, alors info sur les heures escamotée.
  if (isNaN(mm)) mm = '00' // Si valeur nulle, alors affichage par défaut.
  if (isNaN(ss)) ss = '00' // Idem.
  return [hh, mm, ss].filter(Boolean).join(':')
}

const mediaDuration = (media, output) => {
  output.value = secondsToTime(media.duration)
}

const togglePlayPause = media => media.paused ? media.play() : media.pause()

function mute(player) {
  const media = player.previousElementSibling
  media.volume === 0 ? media.volume = 1 : media.volume = 0
  //audio.loop = true
}

function buttonState(button) {
  if (button.classList.contains('active')) button.classList.remove('active')
  else button.classList.add('active')
}

function init(player) {
  const media = player.previousElementSibling
  const buttonPlay = player.querySelector('.audio-play-pause')
  const buttonVolume = player.querySelector('.audio-volume')
  buttonPlay.addEventListener('click', () => {
    togglePlayPause(media)
    buttonState(buttonPlay)
    audioSiblingStop(media)
  })
  buttonVolume.addEventListener('click', () => {
    mute(player)
    buttonState(buttonVolume)
  })
  player.previousElementSibling.addEventListener('ended', () => buttonState(buttonPlay)) // Si fin de la lecture.
}

function audioSiblingStop(media) {
  for (const sibling of medias) {
    if (sibling !== media) sibling.paused
  }
}

audioPlayer()

window.addEventListener('load', () => {
  document.querySelectorAll('.audio-player').forEach(player => init(player))
})
