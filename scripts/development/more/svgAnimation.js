// Fonction pour initialiser l'IntersectionObserver et commencer l'observation des SVG
function initSvgObserver() {
  // Vérifier si l'utilisateur n'a pas de préférence pour réduire les animations
  const prefersNormalMotion = window.matchMedia('(prefers-reduced-motion: no-preference)').matches

  if (!prefersNormalMotion) {
    console.log("Les animations sont désactivées car l'utilisateur préfère réduire les animations.")
    return // Ne pas lancer les animations
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

function setSvgAnimationAttributes(path) {
  const initialAttributes = {
    strokeDasharray: path.getAttribute('stroke-dasharray'),
    strokeDashoffset: path.getAttribute('stroke-dashoffset'),
    fill: path.getAttribute('fill'),
    stroke: path.getAttribute('stroke'),
    strokeWidth: path.getAttribute('stroke-width'),
  }

  const pathLength = path.getTotalLength()
  path.setAttribute('stroke-dasharray', pathLength)
  path.setAttribute('stroke-dashoffset', pathLength)
  path.setAttribute('fill', 'transparent')
  path.setAttribute('stroke', 'orange')
  path.setAttribute('stroke-width', '1')

  return { path, ...initialAttributes }
}

// Fonction pour restaurer les attributs SVG après l'animation
function restoreSvgAttributes(initialAttributesList) {
  initialAttributesList.forEach(({ path, strokeDasharray, strokeDashoffset, fill, stroke, strokeWidth }) => {
    strokeDasharray !== null ? path.setAttribute('stroke-dasharray', strokeDasharray) : path.removeAttribute('stroke-dasharray')
    strokeDashoffset !== null ? path.setAttribute('stroke-dashoffset', strokeDashoffset) : path.removeAttribute('stroke-dashoffset')
    fill !== null ? path.setAttribute('fill', fill) : path.removeAttribute('fill')
    stroke !== null ? path.setAttribute('stroke', stroke) : path.removeAttribute('stroke')
    strokeWidth !== null ? path.setAttribute('stroke-width', strokeWidth) : path.removeAttribute('stroke-width')
  })
}

// Fonction pour gérer les classes CSS des éléments SVG
function manageSvgClasses(svg, action) {
  if (action === 'activate') {
    svg.classList.remove('invisible-if-animation')
    svg.classList.add('active')
  } else if (action === 'deactivate') {
    svg.classList.remove('active')
  }
}

// Fonction principale de gestion de la visibilité des SVG
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

// Fonction pour vérifier les SVGs déjà visibles au chargement
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
