'use strict'

// -----------------------------------------------------------------------------
// @section     Support
// @description Détecte les supports et ajoute des classes dans le tag html
// -----------------------------------------------------------------------------

// @documentation Performance pour les selecteurs @see https://jsbench.me/d7kbm759bb/1
// jsDetect :
document.documentElement.classList.replace('no-js', 'js')

// printDetect :
if(!window.print) document.documentElement.classList.add('no-print') // @see Firefox Android a perdu sa fonction d'impression...

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
// @section     Service Worker
// @description Expérience hors ligne pour application web progressive (PWA)
// -----------------------------------------------------------------------------

if ('serviceWorker' in navigator) navigator.serviceWorker.register('serviceWorker.js') //.then(() => console.log("Service worker registered"))

// -----------------------------------------------------------------------------
// @section     Get Scripts
// @description Appel de scripts
// -----------------------------------------------------------------------------

/**
 * @warning Les scripts chargés par ce biais doivent éviter des modifications trop importantes du DOM ou de repeindre la page (reflow and repaint).
 * @param {string} url : une url de script
 * @param {string} hook : le placement du script, 'head' ou 'footer', footer par défaut.
 */

const getScript = (url, hook = 'footer') => new Promise((resolve, reject) => { // @see https://stackoverflow.com/questions/16839698#61903296
  const script = document.createElement('script')
  script.src = url
  script.async = 1
  script.onerror = reject
  script.onload = script.onreadystatechange = () => {
    const loadState = this.readyState
    if (loadState && loadState !== 'loaded' && loadState !== 'complete') return
    script.onload = script.onreadystatechange = null
    resolve()
  }
  if (hook === 'footer') document.body.appendChild(script)
  else if (hook === 'head') document.head.appendChild(script)
  else console.error("Error: le choix de l'élement html pour getScript() n'est pas correct.")
})

const getScripts = (() => {
  //if (document.querySelector('.masonry')) getScript('/scripts/masonry.js')
  if (document.querySelector('[class*=validation]')) getScript('/scripts/formValidation.js')
  if (document.querySelector('[class*=-focus]')) getScript('/scripts/imageFocus.js')
  if (document.querySelector('[class*=accordion]')) getScript('/scripts/accordion.js')
  //if (document.querySelector('[class*=tabs]')) getScript('/scripts/tab.js')
  if (document.querySelector('.pre')) getScript('/scripts/codeBlock.js')
  //if (document.querySelector('.input [type=password]')) getScript('/scripts/readablePassword.js')
  if (document.querySelector('[class^=range]')) getScript('/scripts/range.js')
  if (document.querySelector('.add-line-marks')) getScript('/scripts/lineMark.js')
  //if (document.querySelector('pie-chart')) getScript('/scripts/pieChart.js')
  //if (document.querySelector('bar-chart')) getScript('/scripts/barChart.js')
  //if (document.querySelector('.media')) getScript('/scripts/development/mediaPlayer.js')
  if (document.querySelector('.video-youtube')) getScript('/scripts/youtube.js')
  if (document.querySelector('.client-test')) getScript('/scripts/clientTest.js')
  if (document.querySelector('.map')) getScript('/scripts/map.js')
  if (document.querySelector('.map')) getScript('/libraries/leaflet/leaflet.js')
  if (document.querySelector('[class*=language-]')) getScript('/libraries/prism/prism.js')
  if (document.querySelector('.script-test')) getScript('/scripts/development/testDev.js')
})()


// -----------------------------------------------------------------------------
// @section     Get Styles
// @description Appel de styles
// -----------------------------------------------------------------------------

/**
 * @param {string} url : une url de script
 * @param {string} media : le media pour lequel les styles sont destinés, par défaut : 'all'
 */

 const getStyle = (url, media = 'all') => new Promise((resolve, reject) => { // @see https://stackoverflow.com/questions/16839698#61903296
  const link = document.createElement('link')
  link.rel= 'stylesheet'
  link.href = url
  link.media = media
  //document.head.appendChild(link)
  const target = document.querySelector('[rel=stylesheet]')
  document.head.insertBefore(link, target.nextSibling)
})

const getStyles = (() => {
  if (document.querySelector('pre > code[class*=language]')) getStyle('/styles/prism.css', 'screen')
  if (document.querySelector('[class*=map]')) getStyle('/libraries/leaflet/leaflet.css', 'screen, print')
})()


// -----------------------------------------------------------------------------
// @section     Polyfills
// @description Permettent de compenser un manque de support CSS dans certains navigateurs
// -----------------------------------------------------------------------------

// @note Fallback pour CSS Container Queries et grid layout @affected Firefox en particulier, et les navigateurs moins récents.
// @see https://css-tricks.com/a-new-container-query-polyfill-that-just-works/
// @note Conditional JS : plus performant que de passer par la détection d'une classe dans le HTML comme pour les autres scripts.
const supportContainerQueries = 'container' in document.documentElement.style // Test support des Container Queries (ok pour Chrome, problème avec Firefox)
const supportMediaQueriesRangeContext = window.matchMedia('(width > 0px)').matches // Test support des requêtes média de niveau 4 (Media Query Range Contexts).
const isFirefox = navigator.userAgent.toLowerCase().indexOf('firefox') > -1 // @todo Solution temporaire pour Firefox.

if (!supportContainerQueries || !supportMediaQueriesRangeContext || isFirefox) getStyle('/styles/gridFallback.css', 'screen')

// @affected Firefox =< v108 @note Compense le non support de :has() sur les grilles.
document.querySelectorAll('[class^=grid]').forEach(grid => grid.parentElement.classList.add('parent-grid'))


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
  svgFile = svgFile || 'util'
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

for (const print of document.querySelectorAll('.cmd-print')) print.onclick = () => window.print()

// -----------------------------------------------------------------------------
// @section     GDPR / gprd
// @description Règlement Général sur la Protection des Données
// -----------------------------------------------------------------------------

const gdpr = (() => {
  //const gdprConsent = localStorage.getItem('gdprConsent')
  const template = document.getElementById('gdpr')
  console.log(template)
  const target = document.querySelector('.alert')
  //document.importNode(panel.content, true)
  const clone = template.content.cloneNode(true)
  target.appendChild(clone)
  const panel = document.getElementById('gdpr-see')
  const trueConsentButton = document.getElementById('gdpr-true-consent')
  const falseConsentButton = document.getElementById('gdpr-false-consent')
  if (localStorage.getItem('gdprConsent') === 'yes') panel.style.display = 'none'
  trueConsentButton.addEventListener('click', () => {
    localStorage.setItem('gdprConsent', 'yes')
    panel.style.display = 'none'
  }, false)
  falseConsentButton.addEventListener('click', () => {
    localStorage.setItem('gdprConsent', 'no')
    panel.style.display = 'grid'
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
// @section     Navigation
// @description Menu principal
// -----------------------------------------------------------------------------

const mainMenu = (() => {
  const button = document.querySelector('.cmd-nav'),
        subNav = document.querySelector('.sub-nav'),
        content = document.querySelectorAll('body > :not(.nav')
  button.addEventListener('click', () => {
    document.documentElement.classList.toggle('active')
    document.body.classList.toggle('active')
    button.classList.toggle('active')
    subNav.classList.toggle('active')
    content.forEach(e => e.hasAttribute('inert') ? e.removeAttribute('inert') : e.setAttribute('inert', ''))
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


// -----------------------------------------------------------------------------
// @section     Horizontal progress bar
// @description Barre de progression horizontale
// -----------------------------------------------------------------------------
/*
// @note Intéressant techniquement, mais pas forcément oportun sur le site car fait double emploi avec la barre verticale.
// @note Notre script est une version améliorée du lien suivant.
// @see https://nouvelle-techno.fr/articles/creer-une-barre-de-progression-horizontale-en-haut-de-page

window.onload = () => {
  const el = document.createElement('div')
  el.id = 'progress-page'
  document.body.appendChild(el)
  window.addEventListener('scroll', () => {
    const height = document.documentElement.scrollHeight - window.innerHeight,
          position = window.scrollY,
          width = document.documentElement.clientWidth,
          value = position / height * width
    el.style.width = value + 'px'
  })
}
*/

// -----------------------------------------------------------------------------
// @section     Button Effect
// @description Effect lors du click sur les boutons
// -----------------------------------------------------------------------------

// @affected Chrome mobile uniquement. @note Firefox a adopté une politique restrictive de cet usage via Content Security Policy, iPhone et Mac ne supportent pas l'API vibration.
// @see https://caniuse.com/vibration

function buttonEffect(e) {
  const frame = e.dataset.frame
  if ('vibrate' in navigator) navigator.vibrate(frame ? frame : 200)
}
document.querySelectorAll('button[class*=button]').forEach(e => e && e.addEventListener('click', () => buttonEffect(e), false))


/*
Mode "application" ou "navigateur" :
let displayMode = 'browser'
window.matchMedia('(display-mode: standalone)').addEventListener('change', e => {
  if (e.matches) displayMode = 'standalone'
})
console.log('DISPLAY_MODE_CHANGED', displayMode)
*/

