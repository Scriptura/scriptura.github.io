/**
 * Initialise l'IntersectionObserver pour observer les SVG animés sur la page.
 * Si l'utilisateur a activé la réduction des animations dans ses préférences, les animations ne seront pas déclenchées.
 */
function initSvgObserver() {
  const prefersNormalMotion = window.matchMedia('(prefers-reduced-motion: no-preference)').matches

  if (!prefersNormalMotion) {
    console.log("Les animations sont désactivées car l'utilisateur préfère réduire les animations.")
    return
  }

  const animatedSvgs = document.querySelectorAll('svg.svg-animation')

  if (!animatedSvgs.length) return

  const observerOptions = {
    root: null,
    rootMargin: '0px',
    threshold: 0.5,
  }
  const observer = new IntersectionObserver(handleSvgVisibility, observerOptions)

  animatedSvgs.forEach(svg => observer.observe(svg))
  checkInitialVisibility(animatedSvgs, observer)
}

/**
 * Définit les attributs d'animation des éléments <path> d'un SVG.
 * 
 * @param {SVGPathElement} path - Un élément <path> du SVG.
 * @returns {Object} - Un objet contenant le chemin d'origine et ses attributs initiaux.
 */
function setSvgAnimationAttributes(path) {
  const initialAttributes = {
    strokeDasharray: path.getAttribute('stroke-dasharray'),
    strokeDashoffset: path.getAttribute('stroke-dashoffset'),
    //fill: path.getAttribute('fill'),
    //stroke: path.getAttribute('stroke'),
    //strokeWidth: path.getAttribute('stroke-width'),
  }

  const pathLength = path.getTotalLength()
  path.setAttribute('stroke-dasharray', pathLength)
  path.setAttribute('stroke-dashoffset', pathLength)
  //path.setAttribute('fill', 'transparent')
  //path.setAttribute('stroke', 'orange')
  //path.setAttribute('stroke-width', '1')

  return { path, ...initialAttributes }
}

/**
 * Restaure les attributs des éléments <path> après l'animation.
 * 
 * @param {Array<Object>} initialAttributesList - Liste des objets contenant les éléments <path> et leurs attributs initiaux.
 */
function restoreSvgAttributes(initialAttributesList) {
  initialAttributesList.forEach(({ path, strokeDasharray, strokeDashoffset, fill, stroke, strokeWidth }) => {
    strokeDasharray !== null ? path.setAttribute('stroke-dasharray', strokeDasharray) : path.removeAttribute('stroke-dasharray')
    strokeDashoffset !== null ? path.setAttribute('stroke-dashoffset', strokeDashoffset) : path.removeAttribute('stroke-dashoffset')
    //fill !== null ? path.setAttribute('fill', fill) : path.removeAttribute('fill')
    //stroke !== null ? path.setAttribute('stroke', stroke) : path.removeAttribute('stroke')
    //strokeWidth !== null ? path.setAttribute('stroke-width', strokeWidth) : path.removeAttribute('stroke-width')
  })
}

/**
 * Gère les classes CSS d'un élément SVG pour activer ou désactiver l'animation.
 * 
 * @param {SVGElement} svg - L'élément SVG à manipuler.
 * @param {string} action - L'action à effectuer ('activate' pour activer l'animation, 'deactivate' pour la désactiver).
 */
function manageSvgClasses(svg, action) {
  if (action === 'activate') {
    svg.classList.remove('invisible-if-animation')
    svg.classList.add('active')
  } else if (action === 'deactivate') {
    svg.classList.remove('active')
  }
}

/**
 * Fonction principale pour gérer la visibilité des SVG et déclencher les animations.
 * Appelée par l'IntersectionObserver lorsque les éléments SVG deviennent visibles ou invisibles.
 * 
 * @param {IntersectionObserverEntry[]} entries - Les entrées de l'observateur contenant les éléments SVG.
 * @param {IntersectionObserver} observer - L'instance de l'IntersectionObserver utilisée pour observer les SVG.
 */
async function handleSvgVisibility(entries, observer) {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      const svg = entry.target
      const paths = svg.querySelectorAll('path')

      if (!svg.classList.contains('active')) {
        manageSvgClasses(svg, 'activate')

        const initialAttributesList = [...paths].map(setSvgAnimationAttributes)

        function handleAnimationEnd() {
          restoreSvgAttributes(initialAttributesList)
          manageSvgClasses(svg, 'deactivate')
          svg.removeEventListener('animationend', handleAnimationEnd)
          observer.unobserve(svg) // Optionnel : arrêter d'observer cet élément une fois l'animation terminée
        }

        svg.addEventListener('animationend', handleAnimationEnd)
      }
    }
  })
}

/**
 * Vérifie la visibilité initiale des SVG au chargement de la page et déclenche l'animation si nécessaire.
 * 
 * @param {NodeListOf<SVGElement>} animatedSvgs - Liste des SVGs à observer.
 * @param {IntersectionObserver} observer - L'instance de l'IntersectionObserver utilisée pour observer les SVG.
 */
function checkInitialVisibility(animatedSvgs, observer) {
  animatedSvgs.forEach(svg => {
    const rect = svg.getBoundingClientRect()
    if (rect.top < window.innerHeight && rect.bottom > 0 && rect.left < window.innerWidth && rect.right > 0) {
      // Si le SVG est visible, déclenche l'animation
      handleSvgVisibility([{ target: svg, isIntersecting: true }], observer)
    }
  })
}

// Ecoute de l'événement personnalisé pour démarrer l'observation
document.addEventListener('svgSpriteInlined', initSvgObserver)
