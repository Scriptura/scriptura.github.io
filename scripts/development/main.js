'use strict'

// -----------------------------------------------------------------------------
// @section     Support
// @description Détecte les supports et ajoute des classes dans le tag html
// -----------------------------------------------------------------------------

// @documentation Performance pour les selecteurs @see https://jsbench.me/d7kbm759bb/1
const jsDetect = (() => document.documentElement.classList.replace('no-js', 'js'))()

// @see https://stackoverflow.com/questions/4817029/whats-the-best-way-to-detect-a-touch-screen-device-using-javascript
// @deprecated Script remplacé par règle CSS @media (hover hover) and (pointer fine)
/*
const touchDetect = (() => {
  const html = document.documentElement,
        touch = 'ontouchstart' in window || navigator.msMaxTouchPoints // @todo Condition à réévaluer
  touch ? html.classList.add('touch') : html.classList.add('no-touch')
})()
*/


// -----------------------------------------------------------------------------
// @section     Get Scripts
// @description Appel de scripts
// -----------------------------------------------------------------------------

/**
 * @param {string} url : une url de script
 * @param {string} hook : le placement du script, 'head' ou 'footer', footer par défaut.
 */

const getScript = (url, hook = 'footer') => new Promise((resolve, reject) => { // @see https://stackoverflow.com/questions/16839698#61903296
  const script = document.createElement('script')
  script.src = url
  script.async = 1
  script.onerror = reject
  script.onload = script.onreadystatechange = function() {
    const loadState = this.readyState
    if (loadState && loadState !== 'loaded' && loadState !== 'complete') return
    script.onload = script.onreadystatechange = null
    resolve()
  }
  if (hook == 'head') document.head.appendChild(script)
  //else document.body.appendChild(script)
  else if (hook == 'footer') document.body.appendChild(script)
  else console.log('Error: the choice of the html tag for the hook is not correct.')
})

const getScripts = (() => {
  if (document.querySelector('.masonry')) getScript('/scripts/masonry.js')
  if (document.querySelector('[class*=validation]')) getScript('/scripts/formValidation.js')
  if (document.querySelector('[class*=-focus]')) getScript('/scripts/imageFocus.js')
  if (document.querySelector('[class*=accordion]')) getScript('/scripts/accordion.js')
  if (document.querySelector('[class*=tabs]')) getScript('/scripts/tab.js')
  if (document.querySelector('[class*=pre]')) getScript('/scripts/codeBlock.js')
  if (document.querySelector('.input [type=password]')) getScript('/scripts/readablePassword.js')
  if (document.querySelector('[class*=add-line-marks]')) getScript('/scripts/lineMark.js')
  if (document.querySelector('[class*=map]')) getScript('/scripts/map.js')
  if (document.querySelector('[class*=language-]')) getScript('/scripts/prism.js')
  if (document.querySelector('[class*=thumbnail-youtube]')) getScript('/scripts/youtubeVideo.js')
})()


// -----------------------------------------------------------------------------
// @section     Get Styles
// @description Appel de styles
// -----------------------------------------------------------------------------

/**
 * @param {string} url : une url de script
 * @param {string} media : le media pour lequel les styles sont destinés, par défaut : 'screen'
 */

 const getStyle = (url, media = 'screen') => new Promise((resolve, reject) => { // @see https://stackoverflow.com/questions/16839698#61903296
  const link = document.createElement('link')
  link.rel= 'stylesheet'
  link.href = url
  link.media = media
  //document.head.appendChild(link)
  const target = document.querySelector('[rel=stylesheet]')
  document.head.insertBefore(link, target.nextSibling)
})

const getStyles = (() => {
  if (document.querySelector('pre > code[class*=language]')) getStyle('/styles/prism.css')
})()


// -----------------------------------------------------------------------------
// @section     Utilities
// @description Utilitaires consommables pour les autres fonctions
// -----------------------------------------------------------------------------

// @documentation Performance pour le script @see https://jsbench.me/trkbm71304/
//const siblings = el => {
//  for (const sibling of el.parentElement.children) if (sibling !== el) sibling.classList.add('color')
//}

const fadeOut = (el, duration) => {
  el.style.opacity = 1
  (function fade() {
    if ((el.style.opacity -= 30 / duration) < 0) {
      el.style.opacity = 0 // reset derrière la décrémentation
      el.style.display = 'none'
    } else {
      requestAnimationFrame(fade)
    }
  })()
}

const fadeIn = (el, duration) => {
  el.style.opacity = 0
  el.style.display = 'block'
  (function fade() {
    let op = parseFloat(el.style.opacity)
    if (!((op += 30 / duration) > 1)) {
      el.style.opacity = op
      requestAnimationFrame(fade)
    }
    if (op > .99) el.style.opacity = 1 // reset derrière l'incrémentation
  })()
}


// -----------------------------------------------------------------------------
// @section     Sprites SVG
// @description Injection de spites SVG
// -----------------------------------------------------------------------------

// @params :
// - `targetElement` : élément cible
// - `spriteId` : nom du sprite
// - `svgFile` : nom du fichier de sprite (`utils.svg` par défaut)
const injectSvgSprite = (targetElement, spriteId, svgFile) => {
  const path = '/sprites/' // Chemin des fichiers de sprites SVG
  if (svgFile === undefined) svgFile = 'utils'
  const icon = `<svg role="img" focusable="false"><use href="${path + svgFile}.svg#${spriteId}"></use></svg>`
  targetElement.insertAdjacentHTML('beforeEnd', icon)
}


// -----------------------------------------------------------------------------
// @section     External links
// @description Gestion des liens externes au site
// -----------------------------------------------------------------------------

// @note Par défaut tous les liens externes conduisent à l'ouverture d'un nouvel onglet, sauf les liens internes

const externalLinks = (() => {
  document.querySelectorAll('a').forEach(a => {
    if (a.hostname !== window.location.hostname) a.setAttribute('target', '_blank')
  })
})()


// -----------------------------------------------------------------------------
// @section     Cmd Print
// @description Commande pour l'impression
// -----------------------------------------------------------------------------

const cmdPrint = (() => {
  const prints = document.querySelectorAll('.cmd-print'),
        startPrint = () => window.print()
  for (const print of prints) print.onclick = startPrint
})()

// -----------------------------------------------------------------------------
// @section     RGPD
// @description Règlement Général sur la Protection des Données
// -----------------------------------------------------------------------------

const rgpd = (() => {
  const rgpdConsent = localStorage.getItem('rgpdConsent')
  const template = document.getElementById('rgpd')
  console.log(template)
  //const target = document.getElementsByTagName('main')[0]
  const target = document.querySelector('.alert')
  //document.importNode(panel.content, true)
  const clone = template.content.cloneNode(true)
  target.appendChild(clone)
  const panel = document.getElementById('rgpd-see')
  const trueConsentButton = document.getElementById('rgpd-true-consent')
  const falseConsentButton = document.getElementById('rgpd-false-consent')
  if (localStorage.getItem('rgpdConsent') === 'yes') panel.style.display = 'none'
  trueConsentButton.addEventListener('click', () => {
    localStorage.setItem('rgpdConsent', 'yes')
    panel.style.display = 'none'
  }, false)
  falseConsentButton.addEventListener('click', () => {
    localStorage.setItem('rgpdConsent', 'no')
    panel.style.display = 'block'
  }, false)
})()


// -----------------------------------------------------------------------------
// @section     Dates
// @description Champs pour les dates
// -----------------------------------------------------------------------------

const dateInputToday = (() => { // @note Date du jour si présence de la classe 'today-date' @see https://css-tricks.com/prefilling-date-input/
  document.querySelectorAll('input[type="date"].today-date').forEach(e => e.valueAsDate = new Date())
})()


// -----------------------------------------------------------------------------
// @section     Multiple Select
// @description Modification du champ html de selection multiple
// -----------------------------------------------------------------------------

const multipleSelectCustom = (() => {
  document.querySelectorAll('.input select[multiple]').forEach(select => {
    const maxLength = 7,
          length = select.length
    if(length < maxLength) { // @note Permet d'afficher toutes les options du sélecteur multiple à l'écran (pour les desktops)
      select.size = length
      select.style.overflow = 'hidden'
    } else {
      select.size = maxLength
    }
  })
})()


// -----------------------------------------------------------------------------
// @section     Range inputs
// @description Slide de valeurs
// -----------------------------------------------------------------------------

const rangeInput = (() => {
  document.querySelectorAll('.range').forEach(range => {
	  const input = range.querySelector('input')
	  const output = range.querySelector('output')
		output.textContent = input.value
		input.oninput = function() {
			output.textContent = this.value
		}
  })
})()


// -----------------------------------------------------------------------------
// @section     Color inputs
// @description Champs pour les couleurs
// -----------------------------------------------------------------------------

const colorInput = (() => {
  document.querySelectorAll('.color-output input').forEach(input => {
    const output = document.createElement('output')
    input.after(output)
    const outputSelector = input.parentElement.querySelector('output')
		output.textContent = input.value
    //outputSelector.style.color = input.value
		input.oninput = function() {
      this.value = this.value
			output.textContent = this.value
      //outputSelector.style.color = this.value
		}
  })
})()


// -----------------------------------------------------------------------------
// @section     Scroll To Top
// @description Défilement vers le haut
// -----------------------------------------------------------------------------

// 1. @see http://jsfiddle.net/smc8ofgg/
// 2. Scrool sur la demi-hauteur d'une fenêtre avant apparition de la flèche.

const scrollToTop = (() => {
  const footer = document.querySelector('.footer'),
        button = document.createElement('button')
  button.type = 'button'
  button.classList.add('scroll-top')
  button.setAttribute('aria-label', 'Scroll to top')
  injectSvgSprite(button, 'arrow-up')
  footer.appendChild(button)
  const item = document.querySelector('.scroll-top')
  item.classList.add('hide')
  const position = () => { // 1
    const yy = window.innerHeight / 2 // 2
    let y = window.scrollY
    if (y > yy) item.classList.remove('hide')
    else item.classList.add('hide')
  }
  window.addEventListener('scroll', position)
  const scroll = () => { // 3
    window.scrollTo({top: 0})
  }
  item.addEventListener('click', scroll, false)
})()

/*
// Solution avec algorythme :
// @see https://stackoverflow.com/questions/15935318/smooth-scroll-to-top/55926067
// @note Script avec un effet sympa mais en conflit avec la règle CSS scroll-behavior:smooth, celle-ci doit donc être désactivée pour la durée du script.

const c = document.documentElement.scrollTop || document.body.scrollTop,
      html = document.documentElement,
      sb = window.getComputedStyle(html,null).getPropertyValue('scroll-behavior')
if (sb != 'auto') html.style.scrollBehavior = 'auto' // 4
if (c > 0) {
  window.requestAnimationFrame(scroll)
  window.scrollTo(0, c - c / 8)
}
if (sb != 'auto') html.style.scrollBehavior = ''

// L'effet behavior:smooth pourrait simplement être défini ainsi en JS (sans conflit avec CSS mais second choix pour l'animation) :

//window.scrollTo({top: 0, behavior: 'smooth'})

// Solution avec une définition scroll-behavior:smooth dans le CSS :

window.scrollTo({top: 0})
*/


// -----------------------------------------------------------------------------
// @section     Main menu
// @description Menu principal
// -----------------------------------------------------------------------------

const mainMenu = (() => {
  const button = document.querySelector('.cmd-nav'),
        mainNav = document.querySelector('.main-nav')

  //const pannel = navigation.querySelector('a')
  //if (window.innerWidth < '1372') Array.from(pannel).map(a => a.tabIndex = -1)

  button.addEventListener('click', () => {
    button.classList.toggle('active')
    mainNav.classList.toggle('active')
    document.body.classList.toggle('active')
  })
})()


// -----------------------------------------------------------------------------
// @section     Drop cap
// @description Création de lettrines
// -----------------------------------------------------------------------------

// @note Les propriétés applicables au pseudo-élément ::first-letter varient d'un navigateur à l'autre ; la solution retenue est un wrapper en javascript 'span.dropcap' sur la première lettre.
// @note Ajout d'une class .dropcap sur le premier caractère du premier paragraphe enfant d'un élément comportant '.add-dropcap'.
// @todo À convertir côté backend dans un helper.

const addDropCap = (() => {
  document.querySelectorAll('.add-drop-cap > p:first-child').forEach(
    e => e.innerHTML = e.innerHTML.replace(/^(\w)/, '<span class="drop-cap">$1</span>')
  )
})()


// -----------------------------------------------------------------------------
// @section     Seconds to time
// @description Conversion d'un nombre de secondes au format hh:mm:ss
// -----------------------------------------------------------------------------

const secondsToTime = e => { // @see https://stackoverflow.com/questions/3733227/javascript-seconds-to-minutes-and-seconds
  let hh = Math.floor(e / 3600).toString().padStart(2, '0'),
      mm = Math.floor(e % 3600 / 60).toString().padStart(2, '0'),
      ss = Math.floor(e % 60).toString().padStart(2, '0')
  if (hh == '00') hh = null // Si pas d'heures, alors info sur les heures escamotée
  return [hh, mm, ss].filter(Boolean).join(':')
}


// -----------------------------------------------------------------------------
// @section     Audio players
// @description Lecteur audio utilisant la spécification HTMLMediaElement
// -----------------------------------------------------------------------------

const audioPlayer = (() => {

  const audios = document.querySelectorAll('.audio')

  const audioDuration = (audio, i) => {
    const output = document.querySelector('.audio-player-duration')
    //console.log(secondsToTime(audio.duration))
    output.value = secondsToTime(audio.duration)
  }

  const addAudioPlayer = (() => {
    let i = 0
    for (const audio of audios) {
      i++
      const player = `<div class="audio-player"><button class="audio-play-pause"><svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><path d="M204.524 102.03L819.48 512 204.523 921.97z"/></svg></button><output class="audio-player-current-time">0:00</output><div class="progress"></div><output class="audio-player-duration">0:00</output><div><button onclick="document.document.getElementById('audio-player${i}')[0].volume += 0.1">+</button><button onclick="document.getElementById('audio-player${i}')[0].volume -= 0.1">-</button></div></div>`
      audio.id = 'audio-player' + i
      audio.insertAdjacentHTML('afterend', player)
      audio.addEventListener('loadedmetadata', audioDuration(audio, i))
    }
  })()

})()


// -----------------------------------------------------------------------------
// @section     Progress Bar
// @description Barre de progression
// -----------------------------------------------------------------------------

const progressBar = (() => {
  document.querySelectorAll('.progress-bar').forEach(e => {
    e.insertAdjacentHTML('afterbegin', '<div></div>')
    e.querySelector('div').style.width = e.dataset.value + '%'
  })
})()

const progressBarTest = (() => {
  const cmd = document.querySelector('#progress-test-cmd'),
        target = document.querySelector('#progress-test-target')
  cmd.addEventListener('click', () => {
    let value = target.dataset.value
    setInterval(frame, 20)
        function frame() {
        if ( value < 100 ) {
          value++
          target.querySelector('div').style.width = value + '%'
        }
      }
  }, false)
})()

// -----------------------------------------------------------------------------
// @section     Postponed footnotes
// @description Report des notes de bas de page au côté du texte
// -----------------------------------------------------------------------------
/*
const footnotes = (() => {
  const notes = document.querySelectorAll('.footnotes > *')
  let id = 1
  for (const note of notes) {
    const a = document.querySelector('#r' + id)
    const clone = note.cloneNode(true)
    clone.classList.add('note')
    a.appendChild(clone)
    //a.insertAdjacentHTML('afterEnd', clone)
    id++
  }
})()
*/
