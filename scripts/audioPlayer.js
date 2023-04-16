'use strict'

const secondsToTime = e => { // @see https://stackoverflow.com/questions/3733227/javascript-seconds-to-minutes-and-seconds
  let hh = Math.floor(e / 3600).toString().padStart(2, '0'),
      mm = Math.floor(e % 3600 / 60).toString().padStart(2, '0'),
      ss = Math.floor(e % 60).toString().padStart(2, '0')
  if (hh == '00') hh = null // Si pas d'heures, alors info sur les heures escamotée
  return [hh, mm, ss].filter(Boolean).join(':')
}

const audioPlayer = (() => {

  const audios = document.querySelectorAll('.audio')

  const audioDuration = (audio, output) => {
    output.value = secondsToTime(audio.duration)
  }

  const addAudioPlayer = (() => {
    let i = 0
    for (const audio of audios) {
      i++
      const player = `
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
      audio.id = 'audio-player' + i
      audio.insertAdjacentHTML('afterend', player)
      const output = audio.nextElementSibling.querySelector('.audio-player-duration')
      audio.addEventListener('loadedmetadata', audioDuration(audio, output))
    }
  })()

})()

function play(player) {
  const audio = player.previousElementSibling
  audio.paused ? audio.play() : audio.pause()
}

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
  buttonPlay.addEventListener('click', () => {
    play(player)
    buttonState(buttonPlay)
  })
  const buttonVolume = player.querySelector('.audio-volume')
  buttonVolume.addEventListener('click', () => {
    mute(player)
    buttonState(buttonVolume)
  })
  player.previousElementSibling.addEventListener('ended', () => buttonState(buttonPlay)) // Si fin de la lecture.
}



document.querySelectorAll('.audio-player').forEach(e => init(e))
