'use strict'

const audioPlayer = () => {

  const audios = document.querySelectorAll('.audio')

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
    for (const audio of audios) {
      i++
      audio.id = 'audio-player' + i
      audio.insertAdjacentHTML('afterend', audioPlayer)
      const output = audio.nextElementSibling.querySelector('.audio-player-duration')
      setTimeout(() => audioDuration(audio, output), 80) // Retarde la fonction pour qu'elle ait le temps d'appliquer la valeur à l'output généré en JavaScript.
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
  if (hh == '00') hh = null // Si pas d'heures, alors info sur les heures escamotée
  return [hh, mm, ss].filter(Boolean).join(':')
}

const audioDuration = (audio, output) => {
  output.value = secondsToTime(audio.duration)
}

const togglePlayPause = audio => audio.paused ? audio.play() : audio.pause()

function mute(player) {
  const audio = player.previousElementSibling
  audio.volume === 0 ? audio.volume = 1 : audio.volume = 0
  //audio.loop = true
}

function buttonState(button) {
  if (button.classList.contains('active')) button.classList.remove('active')
  else button.classList.add('active')
}

function init(player) {
  const buttonPlay = player.querySelector('.audio-play-pause')
  const audio = player.previousElementSibling
  buttonPlay.addEventListener('click', () => {
    togglePlayPause(audio)
    buttonState(buttonPlay)
    audioSiblingStop(audio)
  })
  const buttonVolume = player.querySelector('.audio-volume')
  buttonVolume.addEventListener('click', () => {
    mute(player)
    buttonState(buttonVolume)
  })
  player.previousElementSibling.addEventListener('ended', () => buttonState(buttonPlay)) // Si fin de la lecture.
}

function audioSiblingStop(audio) {
  const audios = document.querySelectorAll('.audio')
  for (const sibling of audios) {
    if (sibling !== audio) sibling.paused
  }
}

audioPlayer()
window.addEventListener('load', () => {
  document.querySelectorAll('.audio-player').forEach(e => init(e))
})