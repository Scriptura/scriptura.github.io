'use strict'

// -----------------------------------------------------------------------------
// @section     Support
// @description Détecte les supports et ajoute des classes dans le tag html
// -----------------------------------------------------------------------------

// jsDetect :
// document.documentElement.classList.replace('no-js', 'js') // @note Remplacé par la solution full CSS "@media (scripting: none)"

// printDetect :
window.print || document.documentElement.classList.add('no-print') // @see Firefox Android a perdu sa fonction d'impression...

// touchDetect
// @see https://stackoverflow.com/questions/4817029/whats-the-best-way-to-detect-a-touch-screen-device-using-javascript
// @deprecated Script remplacé par règle CSS @media (hover hover) and (pointer fine)

// -----------------------------------------------------------------------------
// @section     Online Status
// @description En ligne ou hors ligne
// -----------------------------------------------------------------------------

// Fonction pour vérifier si l'utilisateur est en ligne ou hors ligne
function updateOnlineStatus() {
  const htmlTag = document.documentElement // Sélectionne la balise <html>
  
  // Ajoute ou supprime la classe "offline" selon l'état de la connexion
  if (navigator.onLine) {
    console.log('online')
    htmlTag.classList.remove('offline')
  } else {
    console.log('offline')
    htmlTag.classList.add('offline')
  }
}

// Écoute les événements 'online' et 'offline'
window.addEventListener('online', updateOnlineStatus)
window.addEventListener('offline', updateOnlineStatus)

// Vérification initiale au chargement de la page
updateOnlineStatus()

// -----------------------------------------------------------------------------
// @section     Service Unavailable
// @description Test de l'indisponibilité du service
// -----------------------------------------------------------------------------

// Fonction pour ajouter la classe 'service-unavailable' à l'élément HTML
function addServiceUnavailableClass() {
  document.documentElement.classList.add('service-unavailable')
}

// Ecouter les messages envoyés par le Service Worker
if (navigator.serviceWorker) {
  navigator.serviceWorker.addEventListener('message', event => {
    if (event.data && event.data.action === 'service-unavailable') {
      console.log('Service unavailable (test)')
      addServiceUnavailableClass()
    }
  })
}

// -----------------------------------------------------------------------------
// @section     Service Worker
// @description Expérience hors ligne pour application web progressive (PWA)
// -----------------------------------------------------------------------------

/**
 * Enregistre un Service Worker pour l'application si le navigateur le supporte.
 * @see https://developer.mozilla.org/fr/docs/Web/API/Service_Worker_API/Using_Service_Workers
 * @async
 * @function
 * @returns {Promise<void>} Une promesse qui se résout lorsque l'enregistrement du Service Worker est terminé.
 */
async function registerServiceWorker() {
  if ('serviceWorker' in navigator) {
    try {
      const registration = await navigator.serviceWorker.register('/sw.js')

      if (registration.installing) {
        console.log('Installation du service worker en cours')
      } else if (registration.waiting) {
        console.log('Service worker installé')
      } else if (registration.active) {
        console.log('Service worker actif')
      }
    } catch (error) {
      console.error(`L'enregistrement du service worker a échoué : ${error}`)
    }
  }
}

registerServiceWorker()

// -----------------------------------------------------------------------------
// @section     Get Scripts
// @description Appel de scripts
// -----------------------------------------------------------------------------

/**
 * @warning Les scripts chargés par ce biais doivent éviter des modifications trop importantes du DOM ou de repeindre la page (reflow and repaint).
 * @param {string} url : une url de script
 * @param {string} hook : le placement du script, 'head' ou 'footer', footer par défaut.
 */
const getScript = (url, hook = 'footer') =>
  new Promise((resolve, reject) => {
    // @see https://stackoverflow.com/questions/16839698#61903296
    const script = document.createElement('script')
    script.src = url
    script.async = 1
    script.onerror = reject
    script.onload = script.onreadystatechange = function () {
      const loadState = this.readyState
      if (loadState && loadState !== 'loaded' && loadState !== 'complete') return
      script.onload = script.onreadystatechange = null
      resolve()
    }
    if (hook === 'footer') document.body.appendChild(script)
    else if (hook === 'head') document.head.appendChild(script)
    else console.error(`Error: le choix de l'élement HTML pour getScript() n'est pas correct.`)
  })

const getScriptRequests = (() => {
  if (document.querySelector('[class*=language-]')) getScript('/libraries/prism/prism.js')
  if (document.querySelector('.map')) getScript('/libraries/leaflet/leaflet.js')
  const selectors = [
    '[class*=validation]',
    '[class*=assistance]',
    '[class*=character-counter]',
    '[class*=-focus]',
    '.preview-container',
    '[class*=accordion]',
    '.pre',
    '[class^=range]',
    '.add-line-marks',
    '.video-youtube',
    '.client-test',
    '.map',
    '[class*=language-]',
    '.input-add-terms',
    '.flip',
    '.sprite-to-inline',
    '.svg-animation',
  ]
  if (selectors.some(selector => document.querySelector(selector))) getScript('/scripts/more.js')
})()

// -----------------------------------------------------------------------------
// @section     Load Styles
// @description Appel de styles
// -----------------------------------------------------------------------------

/**
 * Fonction permettant d'ajouter un fichier CSS au document
 *
 * @param {string} url - L'URL du fichier CSS à charger
 * @param {string} [media='all'] - Le média pour lequel les styles sont destinés (par défaut : 'all')
 * @returns {Promise<string>} - Une promesse qui est résolue lorsque le fichier CSS est chargé avec succès
 */
function loadStyle(url, media = 'all') {
  return new Promise((resolve, reject) => {
    const link = document.createElement('link')
    link.rel = 'stylesheet'
    link.href = url
    link.media = media
    link.onload = () => resolve(url)
    link.onerror = () => reject(new Error(`Failed to load ${url}`))
    //document.head.appendChild(link)
    const target = document.querySelector('[rel=stylesheet]')
    document.head.insertBefore(link, target.nextSibling)
  })
}

/**
 * Fonction pour charger conditionnellement les styles nécessaires à la page
 */
async function loadConditionalStyles() {
  try {
    if (document.querySelector('pre > code[class*=language]')) {
      await loadStyle('/styles/prism.css', 'screen')
    }
    if (document.querySelector('[class*=map]')) {
      await loadStyle('/libraries/leaflet/leaflet.css', 'screen, print')
    }
  } catch (error) {
    console.error('Erreur de chargement des styles:', error)
  }
}

loadConditionalStyles()

// -----------------------------------------------------------------------------
// @section     Polyfills
// @description Permettent de compenser un manque de support CSS dans certains navigateurs
// -----------------------------------------------------------------------------
/*
// @note Fallback pour CSS Container Queries et grid layout @affected Firefox en particulier, et les navigateurs moins récents.
// @see https://css-tricks.com/a-new-container-query-polyfill-that-just-works/
// @note Conditional JS : plus performant que de passer par la détection d'une classe dans le HTML comme pour les autres scripts.
const supportContainerQueries = 'container' in document.documentElement.style // Test support des Container Queries (ok pour Chrome, problème avec Firefox)
const supportMediaQueriesRangeContext = window.matchMedia('(width > 0px)').matches // Test support des requêtes média de niveau 4 (Media Query Range Contexts).
const isFirefox = navigator.userAgent.toLowerCase().indexOf('firefox') > -1 // @todo Solution temporaire pour Firefox.

if (!supportContainerQueries || !supportMediaQueriesRangeContext || isFirefox) {
  getStyle('/styles/gridFallback.css', 'screen')
  document.querySelectorAll('[class^=grid]').forEach(grid => grid.parentElement.classList.add('parent-grid')) // @affected Firefox =< v108 @note Compense le non support de :has() sur les grilles.
}
*/

// -----------------------------------------------------------------------------
// @section     Preload Images
// @description Précharge les images ayant l'attribut loading="lazy"
// -----------------------------------------------------------------------------

/**
 * Précharge les images ayant l'attribut loading="lazy"
 * en les téléchargeant après le chargement complet de la page.
 * Cela permet d'améliorer les performances lors d'une navigation ultérieure.
 * Notamment pour l'utilisation du cache avec un Service Worker.
 */
 function preloadImages() {
  const images = document.querySelectorAll('img[loading="lazy"]')

  images.forEach(img => {
    const preloadedImage = new Image()
    preloadedImage.src = img.src
  })
}

window.addEventListener('load', preloadImages)

// -----------------------------------------------------------------------------
// @section     Sprites SVG
// @description Injection de spites SVG
// -----------------------------------------------------------------------------

/**
 * Injecte un sprite SVG dans un élément cible.
 *
 * @param {HTMLElement} targetElement - L'élément dans lequel le sprite SVG sera injecté.
 * @param {string} spriteId - L'identifiant du sprite à injecter.
 * @param {string} [svgFile='util'] - Le nom du fichier de sprite (par défaut 'util' si non fourni).
 */
function injectSvgSprite(targetElement, spriteId, svgFile) {
  const path = '/sprites/' // Chemin des fichiers de sprites SVG
  svgFile = svgFile || 'util'
  const icon = `<svg role="img" focusable="false"><use href="${path + svgFile}.svg#${spriteId}"></use></svg>`
  targetElement.insertAdjacentHTML('beforeEnd', icon)
}

// -----------------------------------------------------------------------------
// @section     External links
// @description Gestion des liens externes au site
// -----------------------------------------------------------------------------

/**
 * Ouvre tous les liens externes dans un nouvel onglet, sauf les liens internes.
 * @note Par défaut, tous les liens externes conduisent à l'ouverture d'un nouvel onglet, sauf les liens internes.
 */
function openExternalLinksInNewTab() {
  const links = document.querySelectorAll('a')

  for (const link of links) {
    if (link.hostname !== window.location.hostname) {
      link.setAttribute('target', '_blank')
    }
  }
}

openExternalLinksInNewTab()

// -----------------------------------------------------------------------------
// @section     Cmd Print
// @description Commande pour l'impression
// -----------------------------------------------------------------------------

/**
 * Ajoute un gestionnaire d'événement 'click' sur tous les éléments avec la classe '.cmd-print'
 * pour déclencher l'impression de la fenêtre.
 */
function addPrintEventListener() {
  const printButtons = document.querySelectorAll('.cmd-print')

  for (const printButton of printButtons) {
    printButton.onclick = function () {
      window.print()
    }
  }
}

addPrintEventListener()

// -----------------------------------------------------------------------------
// @section     GDPR / gprd
// @description Règlement Général sur la Protection des Données
// -----------------------------------------------------------------------------

const gdpr = (() => {
  //const gdprConsent = localStorage.getItem('gdprConsent')
  const template = document.getElementById('gdpr')
  //console.log(template)
  const target = document.querySelector('.alert')
  //document.importNode(panel.content, true)
  const clone = template.content.cloneNode(true)
  target.appendChild(clone)
  const panel = document.getElementById('gdpr-see')
  const trueConsentButton = document.getElementById('gdpr-true-consent')
  const falseConsentButton = document.getElementById('gdpr-false-consent')
  if (localStorage.getItem('gdprConsent') === 'yes') panel.style.display = 'none'
  trueConsentButton.addEventListener(
    'click',
    () => {
      localStorage.setItem('gdprConsent', 'yes')
      panel.style.display = 'none'
    },
    false,
  )
  falseConsentButton.addEventListener(
    'click',
    () => {
      localStorage.setItem('gdprConsent', 'no')
      panel.style.display = 'none' // 'grid'
    },
    false,
  )
})()

// -----------------------------------------------------------------------------
// @section     Dates
// @description Champs pour les dates
// -----------------------------------------------------------------------------

const dateInputToday = (() => {
  // @note Date du jour si présence de la classe 'today-date' @see https://css-tricks.com/prefilling-date-input/
  document.querySelectorAll('input[type=date].today-date').forEach(e => (e.valueAsDate = new Date())) // @bugfixed Semble problématique sur certains navigateurs. @todo À voir dans le temps.
})()

// -----------------------------------------------------------------------------
// @section     Multiple Select
// @description Modification du champ html de selection multiple
// -----------------------------------------------------------------------------

const multipleSelectCustom = (() => {
  document.querySelectorAll('.input select[multiple]').forEach(select => {
    const maxLength = 7,
      length = select.length
    if (length < maxLength) {
      // @note Permet d'afficher toutes les options du sélecteur multiple à l'écran (pour les desktops)
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
  document.querySelectorAll('.input:has([type=color] + output) input').forEach(input => {
    const output = input.nextElementSibling
    output.textContent = input.value
    input.oninput = function () {
      this.value = this.value
      output.textContent = this.value
    }
  })
})()

// -----------------------------------------------------------------------------
// @section     Scroll To Top
// @description Défilement vers le haut
// -----------------------------------------------------------------------------

function scrollToTop() {
  const footer = document.querySelector('.footer')
  const button = document.createElement('button')

  button.type = 'button'
  button.classList.add('scroll-top')
  button.setAttribute('aria-label', 'Scroll to top')
  injectSvgSprite(button, 'arrow-up')
  footer.appendChild(button)

  const item = document.querySelector('.scroll-top')
  item.classList.add('fade-out')

  function position() {
    const yy = window.innerHeight / 2 // @note Scroll sur la demi-hauteur d'une fenêtre avant apparition de la flèche.
    let y = window.scrollY
    if (y > yy) {
      item.classList.remove('fade-out')
      item.classList.add('fade-in')
    } else {
      item.classList.add('fade-out')
      item.classList.remove('fade-in')
    }
  }

  window.addEventListener('scroll', position)

  function scroll() {
    window.scrollTo({ top: 0 })
  }

  item.addEventListener('click', scroll, false)
}

scrollToTop()

// -----------------------------------------------------------------------------
// @section     Navigation
// @description Menu principal
// -----------------------------------------------------------------------------

const mainMenu = (() => {
  const button = document.querySelector('.cmd-nav'),
    subNav = document.querySelector('.sub-nav'),
    content = document.querySelectorAll('body > :not(.nav'),
    sizeNav = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--size-nav')),
    htmlFontSize = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('font-size'))

  button.ariaExpanded = 'false'
  subNav.ariaHidden = 'false'

  const toggleNavigation = () => {
    document.documentElement.classList.toggle('active')
    document.body.classList.toggle('active')
    button.ariaExpanded = button.ariaExpanded === 'true' ? 'false' : 'true'
    subNav.ariaHidden = subNav.ariaHidden === 'true' ? 'false' : 'true'
    content.forEach(e => (e.hasAttribute('inert') ? e.removeAttribute('inert') : e.setAttribute('inert', '')))
  }

  button.addEventListener('click', e => {
    toggleNavigation()
    //e.preventDefault()
  })

  const clearMenu = () => {
    const windowWidth = window.innerWidth / htmlFontSize
    if (sizeNav < windowWidth && button.ariaExpanded === 'true') toggleNavigation()
  }

  window.addEventListener('resize', () => {
    // @note Si le menu déroulant est ouvert, mais que la fenêtre est redimentionnée au-delà de la navigation prévue pour cette version du menu, alors suppression des états prévus pour la version "menu déroulant".
    let resizeTimeout
    clearTimeout(resizeTimeout)
    resizeTimeout = setTimeout(() => {
      clearMenu()
    }, 200) // Limitation du nombre de calculs @see https://stackoverflow.com/questions/5836779/
  })
})()

// -----------------------------------------------------------------------------
// @section     Horizontal progress bar
// @description Barre de progression horizontale
// -----------------------------------------------------------------------------

// @note Solution intéressante techniquement mais pas forcément opportune sur le site car fait double emploi avec la barre verticale.
// @see https://nouvelle-techno.fr/articles/creer-une-barre-de-progression-horizontale-en-haut-de-page
/*
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

// -----------------------------------------------------------------------------
// @section     Go Back
// @description Retour à la page précédente de l'historique de navigation
// -----------------------------------------------------------------------------

function goBack() {
  window.history.back()
}

const goBackElements = document.querySelectorAll('.go-back')

for (const element of goBackElements) {
  element.addEventListener('click', goBack)
}

// -----------------------------------------------------------------------------
// @section     Image Fallback
// @description Fallback pour les images
// -----------------------------------------------------------------------------

/**
 * Initialise le mécanisme de fallback pour les images et les sources d'images.
 * Remplace les images et les sources d'images qui échouent à se charger par une image par défaut (SVG).
 *
 * Fonctionnement :
 * - Pour chaque élément <img>, un gestionnaire d'événement 'error' est ajouté.
 * - Si une image échoue à se charger, elle est remplacée par l'image par défaut.
 * - Pour chaque élément <source> dans un <picture> parent, un gestionnaire d'événement 'error' est ajouté.
 * - Si une source échoue à se charger, elle est remplacée par l'image par défaut.
 */
/* Solution fonctionnelle mais non utilisée en raison de problème de performance (-7 points sous Lighthouse)
function initializeImageFallback() {
  const defaultImageURL = '/medias/icons/utilDest/xmark.svg'
  const urlCache = new Map()

  function testImageURL(url) {
    return new Promise(resolve => {
      if (urlCache.has(url)) {
        resolve(urlCache.get(url))
        return
      }

      const img = new Image()
      img.onload = () => {
        urlCache.set(url, true)
        resolve(true)
      }
      img.onerror = () => {
        urlCache.set(url, false)
        resolve(false)
      }
      img.src = url
    })
  }

  async function replaceSourceWithDefault(sourceElement) {
    const srcset = sourceElement.srcset
    const urls = srcset.split(',').map(src => src.trim().split(' ')[0])
    for (const url of urls) {
      const isValid = await testImageURL(url)
      if (!isValid) {
        sourceElement.srcset = defaultImageURL
        break
      }
    }
  }

  async function replaceImageWithDefault(event) {
    const imgElement = event.target
    imgElement.src = defaultImageURL

    if (!imgElement.hasAttribute('width')) {
      imgElement.setAttribute('width', '1000')
    }
    if (!imgElement.hasAttribute('height')) {
      imgElement.setAttribute('height', '1000')
    }

    const pictureElement = imgElement.closest('picture')
    if (pictureElement) {
      const sources = pictureElement.querySelectorAll('source')
      for (const source of sources) {
        await replaceSourceWithDefault(source)
      }
    }
  }

  const images = document.querySelectorAll('img')

  images.forEach(image => {
    image.addEventListener('error', replaceImageWithDefault)

    testImageURL(image.src).then(isValid => {
      if (!isValid) {
        replaceImageWithDefault({ target: image })
      }
    })
  })
}

window.addEventListener('load', initializeImageFallback)
*/
