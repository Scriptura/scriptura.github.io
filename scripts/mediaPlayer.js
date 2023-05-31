'use strict'

// @see https://developer.mozilla.org/en-US/docs/Web/Guide/Audio_and_video_delivery/cross_browser_video_player
// @see https://developer.mozilla.org/fr/docs/Learn/HTML/Multimedia_and_embedding/Video_and_audio_content

const mediaPlayer = () => {

  const HTMLMediaElement = '.media', // audio, video
        medias = document.querySelectorAll(HTMLMediaElement)

  const playerTemplate = `
  <div class="media-player">
    <button class="media-play-pause" aria-label="play/pause">
      <svg focusable="false">
        <use href="/sprites/player.svg#play"></use>
      </svg>
      <svg focusable="false">
        <use href="/sprites/player.svg#play-disabled"></use>
      </svg>
      <svg focusable="false">
        <use href="/sprites/player.svg#pause"></use>
      </svg>
    </button>
    <div class="media-tags">
      <output class="media-subtitle-langage"></output>
      <output class="media-playback-rate"></output>
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
      <button class="media-subtitles" aria-label="subtitles">
        <svg focusable="false">
          <use href="/sprites/player.svg#subtitles"></use>
        </svg>
        <!--
        <svg focusable="false">
          <use href="/sprites/player.svg#subtitles-off"></use>
        </svg>
        -->
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
          <use href="/sprites/player.svg#slow-motion"></use>
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
    if (hh === '0') hh = null // Si pas d'heures, alors info sur les heures escamotées.
    if (isNaN(hh)) hh = null // Si valeur nulle, alors info sur les heures escamotées.
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

  }

  const currentTime = (media, output, progressBar) => {
    setInterval(frame, 50)
    function frame() {
      const ratio = Math.floor(media.currentTime / media.duration * 1000) / 10 // @note Un chiffre après la virgule.
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

  const replay = media => media.loop = !media.loop

  //const fastRewind = media => {}

  //const fastForward = media => {}

  const leapRewind = media => media.currentTime -= 10

  const leapForward = media => media.currentTime += 10

  const togglePictureInPicture = media => { // @see https://developer.mozilla.org/en-US/docs/Web/API/Picture-in-Picture_API
    if (document.pictureInPictureElement) document.exitPictureInPicture()
    else if (document.pictureInPictureEnabled) media.requestPictureInPicture()
  }

  const ccDisplay = language => `cc: ${language}`

  const subtitles = (tracks, i, output) => { // @see https://developer.mozilla.org/en-US/docs/Web/API/TextTrack
    if (tracks[i -1]) tracks[i -1].mode = 'disabled'
    tracks[i].mode = 'showing'
    const cc = ccDisplay(tracks[i].language)
    output.value = cc
  }

  const playbackRateChange = (media, playbackRateOutput) => {
    //(media.playbackRate > .25) ? media.playbackRate -= .2 : media.playbackRate = 4 // @note Les valeurs ont besoin d'être déterminées précisément car les résultats des soustractions sont approximatifs.
    switch (media.playbackRate) { // @note Plage navigateur recommandée entre 0.25 et 4.0.
      case (1): media.playbackRate = .5
        break
      case (.5): media.playbackRate = .25
        break
      case (.25): media.playbackRate = .1
        break
      case (.1): media.playbackRate = 4
        break
      case (4): media.playbackRate = 2
        break
      case (2): media.playbackRate = 1.5
        break
      default: media.playbackRate = 1
    }
    playbackRateOutput.innerHTML = `x${media.playbackRate}`
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
    document.querySelectorAll('.media-player').forEach(playerItem => {
      if (playerItem !== player) { // @note Si un menu ouvert, alors les menus des autres players sont fermés.
        const menu = playerItem.querySelector('.media-menu')
        const extendMenu = playerItem.querySelector('.media-extend-menu')
        if (menu) menu.classList.remove('active')
        if (extendMenu) extendMenu.classList.remove('active')
      }
    })
  }

  const getNextMedia = (media, mediaRelationship) => {
    if (mediaRelationship) {
      const relatedMedias = mediaRelationship.querySelectorAll(HTMLMediaElement) || ''
      return relatedMedias[[...relatedMedias].indexOf(media) + 1] || relatedMedias[0] || ''
    }
  }

  const getNextNextMedia = (media, mediaRelationship) => {
    if (mediaRelationship) {
      const relatedMedias = mediaRelationship.querySelectorAll(HTMLMediaElement) || ''
      return relatedMedias[[...relatedMedias].indexOf(media) + 2] || relatedMedias[0] || ''
    }
  }

  const nextMediaActive = (media, nextMedia, nextNextMedia, mediaRelationship) => {

    media = nextMedia

    if(media.error) { // Si erreur, passage au media suivant
      console.log(media.error.message)
      return nextMediaActive(media, getNextMedia(media, mediaRelationship), getNextNextMedia(media, mediaRelationship), mediaRelationship)
    }

    //media.currentTime = 0 // @note Désactivée : un utilisateur peut ainsi caler la plage suivante selon sa préférence personnelle.

    const player = media.nextElementSibling,
          playPauseButton = player.querySelector('.media-play-pause'),
          currentTimeOutput = player.querySelector('.media-current-time'),
          progressBar = player.querySelector('.media-progress-bar')

    togglePlayPause(media)
    buttonState(!media.paused, playPauseButton)
    currentTime(media, currentTimeOutput, progressBar)
  }

  const controls = media => {

    const player = media.nextElementSibling,
          tracks = media.textTracks,
          playPauseButton = player.querySelector('.media-play-pause'),
          playbackRateOutput = player.querySelector('.media-playback-rate'),
          subtitleLangageOutput = player.querySelector('.media-subtitle-langage'),
          //time = player.querySelector('.media-time'),
          currentTimeOutput = player.querySelector('.media-current-time'),
          progressBar = player.querySelector('.media-progress-bar'),
          //extendVolume = player.querySelector('.media-extend-volume'),
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
          subtitlesButton = player.querySelector('.media-subtitles'),
          mediaRelationship = media.closest('.media-relationship'),
          nextMedia = getNextMedia(media, mediaRelationship),
          nextNextMedia = getNextNextMedia(media, mediaRelationship)


    // Remove Controls :
    // @note Le code est plus simple et robuste si l'on se contente de supprimer des boutons déjà présents dans le template du player plutôt que de les ajouter (cibler leur place dans le DOM qui peut changer au cours du développement, rattacher les fonctionnalités au DOM...)

    if (media.tagName === 'AUDIO' || !document.fullscreenEnabled) fullscreenButton.remove()
    if (media.tagName === 'AUDIO' || !document.pictureInPictureEnabled) pictureInPictureButton.remove()
    if (!media.textTracks[0]) subtitlesButton.remove()
    if (!mediaRelationship) nextReadingButton.remove()

    // Initialisation de valeurs :

    const initValues = (() => {
      progressBar.value = '0' // Valeur définie aussi dans le template string.
      progressBar.style.setProperty('--position', '0%')
      progressBar.style.setProperty('--position-buffer', '0%')
      volumeBar.value = '.5'
      volumeBar.style.setProperty('--position', '50%')
    })()

    if (mediaRelationship) media.addEventListener('canplay', () => buttonState(mediaRelationship.dataset.nextReading === 'true', media.nextElementSibling.querySelector('.media-next-reading')))

    // Contrôle via les événements :

    // @note Le code récupère l'intégralité des plages téléchargées dans l'objet range et donne une indication de la quantité de médias réellement téléchargés, sans tenir compte de la localisation des plages.
    // @see https://developer.mozilla.org/fr/docs/Web/Guide/Audio_and_video_delivery/buffering_seeking_time_ranges
    // @see https://stackoverflow.com/questions/25651719
    ;['loadeddata', 'progress'].forEach(event => {
      media.addEventListener(event, () => {
        // @note 'media.onprogress' évite une erreur de lecture si avant l'événement 'loadeddata'.
        media.onprogress = () => progressBar.style.setProperty('--position-buffer', `${Math.floor(media.buffered.end(media.buffered.length - 1) / media.duration * 100)}%`) // @note Un nombre entier suffit.
      })
    })

    media.addEventListener('waiting', () => player.classList.add('waiting')) // Si ressource en cours de chargement.
    
    media.addEventListener('canplay', () => player.classList.remove('waiting')) // Si ressource chargée.

    document.addEventListener('play', e => { // @note Si un lecteur actif, alors les autres se mettent en pause.
      medias.forEach(media => (media !== e.target) && media.pause())
      // Avec option '.media-single-player' dans un élément parent :
      //medias.forEach(media => (media.closest('.media-single-player') && media !== e.target) && media.pause())
    }, true)

    ;['click', 'play', 'pause', 'ended', 'input'].forEach(event => { // "timeupdate"
      document.addEventListener(event, () => { // @note Ne mettre ici que les boutons liés au player en cours.
        buttonState(!media.paused, playPauseButton)
        buttonState(media.muted || media.volume === 0, muteButton)
        buttonState(media.paused && media.currentTime === 0, stopButton)
        buttonState(media.loop, replayButton)
        media.paused && media.currentTime === 0 ? stopButton.disabled = true : stopButton.disabled = false
        // @note Variable CSS pilotée par JS ; permet de reprendre l'animation là où elle s'est arrêtée :
        //media.paused && playPauseButton.style.setProperty('--play-state', running === 'running' ? 'paused' : 'running')
      })
    })

    media.addEventListener('ended', () => {
      //media.currentTime = 0 // @note Permet de réinitialiser la lecture, mais le fait de s'abstenir de réinitialiser permet de mieux repérer les fichiers déjà lus.
      playPauseButton.classList.remove('active')
      stopButton.classList.add('active')
      stopButton.disabled = true
      if (mediaRelationship && mediaRelationship.dataset.nextReading === 'true' && media.play) nextMediaActive(media, nextMedia, nextNextMedia, mediaRelationship) // @note Si media appartenant à un groupe, lecture du media suivant (n+1).
      if (mediaRelationship && mediaRelationship.dataset.nextReading && nextMedia) nextNextMedia.preload = 'auto' // @note Si media appartenant à un groupe, indiquation au navigateur de la possibilité de charger le media n+2 @todo En test.
    })

    media.addEventListener('pause', () => playPauseButton.classList.remove('active'))

    // Contrôle via les boutons :

    playPauseButton.addEventListener('click', () => {
      togglePlayPause(media)
      currentTime(media, currentTimeOutput, progressBar)
      menu(player, false)
      if (mediaRelationship && mediaRelationship.dataset.nextReading && nextMedia) nextMedia.preload = 'auto' // @note Si media d'un groupe, on indique au navigateur la possibilité de charger le media suivant @todo En test.
    })

    muteButton.addEventListener('click', () => mute(media)) //if (!media.muted && media.volume === 0) media.volume = .5

    progressBar.addEventListener('input', () => {
      media.currentTime = (progressBar.value / progressBar.max) * media.duration
      currentTime(media, currentTimeOutput, progressBar)
    })

    volumeBar.addEventListener('input', () => {
      const position = volumeBar.value / volumeBar.max
      media.volume = position
      volumeBar.style.setProperty('--position', `${position * 100}%`)
    })

    menuButton.addEventListener('click', () => { // @note Fonction propre au player, non liée à la source mediaElement.
      menu(player, true)
      menuButton.classList.toggle('active')
      // @todo BEGIN test
      // @note Méthode en test car un peu lourde pour déterminer du style.
      try { // Solution de repli pour ".media-extend-menu" si règle CSS :has() non supportée
        document.querySelector('body:has(*)')
      } catch {
        console.log('Solution de repli JS pour ".media-extend-menu"')
        const extendMenu = player.querySelector('.media-extend-menu'),
              numberButtons = extendMenu.querySelectorAll('button').length
        let rows = numberButtons
        if (numberButtons > 12) rows = 6
        else if (numberButtons > 6) rows = Math.ceil(numberButtons / 2) // Distribution des bouttons sur 2 lignes de manière équitable.
        extendMenu.style.setProperty('--mem', rows)
        console.log(rows)
      }
      // @todo END test
    })

    nextReadingButton.addEventListener('click', () => {
      mediaRelationship.dataset.nextReading === 'false' ? mediaRelationship.dataset.nextReading = 'true' : mediaRelationship.dataset.nextReading = 'false'
      mediaRelationship.querySelectorAll(HTMLMediaElement).forEach(media => { // @note Il peut s'agir de n'importe lequel des medias du groupe en relation.
        if (mediaRelationship.dataset.nextReading === 'true') media.loop = false
        buttonState(mediaRelationship.dataset.nextReading === 'true', media.nextElementSibling.querySelector('.media-next-reading'))
      })
    })

    // @see https://developer.mozilla.org/en-US/docs/Web/Guide/Audio_and_video_delivery/Adding_captions_and_subtitles_to_HTML5_video
    let count = -1

    subtitlesButton.addEventListener('click', () => {
      count += 1
      //if (tracks[count] === tracks[0]) tracks[count +1]
      
      if (count > 1) tracks[count -1].mode = 'disabled'
      if (count < tracks.length) {
        if (tracks[count].mode === 'showing') count += 1 // Si un track est définit par défaut dans le HTML, on le saute pour la première série de clique.
        subtitles(tracks, count, subtitleLangageOutput)
        buttonState(tracks[count].mode === 'showing', subtitlesButton)
        buttonState(tracks[count].mode === 'showing', subtitleLangageOutput)
      } else {
        count = -1
        subtitleLangageOutput.value = ''
        subtitlesButton.classList.remove('active')
        subtitleLangageOutput.classList.remove('active')
      }
    })

    for(let track of tracks) {
      if (track.mode === 'showing') { // @note Si balise <track> dotée d'un attribut "default"
        subtitlesButton.classList.add('active')
        subtitleLangageOutput.classList.add('active')
        subtitleLangageOutput.value = ccDisplay(track.language)
        break // @note Solution possible car une seule occurence à tester @todo À évaluer.
      }
    }

    if (media.tagName === 'VIDEO' && document.fullscreenEnabled) fullscreenButton.addEventListener('click', () => fullscreen(media))

    document.addEventListener('fullscreenchange', () => fullscreenButton.classList.toggle('active')) // @note Pour le fun, car l'état du bouton ne se voit pas... sauf peut-être sur des configurations multi écran.

    pictureInPictureButton.addEventListener('click', () => {
      togglePictureInPicture(media)
      buttonState(!document.pictureInPictureElement, pictureInPictureButton) // @note Ne pas mettre avec les clics généraux car cette fonction est en lien avec tous les players, pas seulement le player actuel.
    })

    slowMotionButton.addEventListener('click', () => {
      playbackRateChange(media, playbackRateOutput)
      buttonState(media.playbackRate !== 1, slowMotionButton) // @note Toujours placé après la fonction playbackRateChange()
      if (media.playbackRate !== 1) playbackRateOutput.classList.add('active') // @note Une fois activé on laisse l'affichage, même si retour à la valeur d'origine.
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

    replayButton.addEventListener('click', () => replay(media))

  }

  const error = media => {
    // @see https://html.spec.whatwg.org/multipage/media.html#error-codes

    const player = media.nextElementSibling,
          time = player.querySelector('.media-time')

    media.src = media.currentSrc // @note Afin de rendre possible la lecture des erreurs via un gestionnaire d'événement, on lit la source présente dans le HTML puis on la réaffecte via JS. @see https://forum.alsacreations.com/topic-5-90423-1-Resolu-Lecteur-audiovideo-HTMLMediaElement--gestion-des-erreurs.html#lastofpage

    media.addEventListener('error', () => {
      player.setAttribute('inert', '')
      player.querySelectorAll('button, input').forEach(e => e.disabled = true) // @note Pour les anciens navigateurs.
      media.classList.add('error')
      player.classList.add('error')
      
      console.error(media.error.message)
      time.innerHTML = 'Erreur de lecture'

      media.poster = ''
      
      /*
      const div = document.createElement('div')
      div.classList.add('video-error')
      div.innerHTML = `<svg class="icon scale250" role="img" focusable="false"><use href="/sprites/util.svg#space-invader"></use></svg>`
      if (media.tagName === 'VIDEO') media.insertAdjacentElement('beforeend', div)
      */
    
    }, true)
  }

  let i = 0
  for (const media of medias) {
    i++
    media.id = 'media-' + i
    media.removeAttribute('controls') // @note C'est bien Javascript qui doit se charger de cette opération, CSS ne doit pas le faire, ce qui permet un lecteur par défaut avec l'attribut "controls" si JS désactivé.
    addPlayer(media)
    controls(media)
    error(media)
  }

}

window.addEventListener('DOMContentLoaded', mediaPlayer()) // @note S'assurer que le script est bien chargé après le DOM et ce quelque soit la manière dont il est appelé.
