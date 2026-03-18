'use strict'

/**
 * @summary Injection de marqueurs de ligne numérotés et navigation par ancre dans les
 *          pages article. Chaque élément cible reçoit une ancre `#mark-N` navigable.
 *
 * @strategy
 *   – Sélecteur déclaré comme constante AOT : évalué une fois, jamais recalculé.
 *   – Création des nœuds <a> en boucle synchrone : le DOM est stable avant tout
 *     appel de scroll, sans recours à un événement différé.
 *
 * @architectural-decision
 *   – Le scroll-to-hash est intentionnellement différé de SCROLL_DELAY ms après le boot.
 *     Ce délai n'est pas un correctif technique : c'est une décision UX. L'utilisateur
 *     doit avoir le temps de percevoir la page chargée avant que le défilement ne
 *     s'opère, ce qui lui fournit une indication visuelle explicite de sa position de
 *     navigation dans la page. L'effet repose sur scroll-behavior: smooth déclaré sur
 *     <html> en CSS : sans cette règle, le scroll est instantané et l'intention UX est
 *     perdue.
 *   – Sélecteur explicite (:where(p, h2, ...)) préféré au sélecteur universel '*' avec
 *     exclusions : coût de matching inférieur, intention déclarative.
 *   – Null-guard sur querySelector(hash) : un hash malformé ou orphelin ne doit pas
 *     produire de throw silencieux.
 */
const LineMarkSystem = (() => {

  // ---------------------------------------------------------------------------
  // 1. Data Layout
  // ---------------------------------------------------------------------------

  // @note Pour un meilleur contrôle, les éléments cibles sont listés explicitement
  //       plutôt qu'utilisés avec le sélecteur universel '*' par exclusion.
  const SELECTOR = '.add-line-marks > :where(p, h2, h3, h4, h5, h6, blockquote, ul, ol, [class*=grid])'

  // Délai UX intentionnel : laisse le temps à l'utilisateur de percevoir la page
  // avant le défilement automatique vers l'ancre cible.
  const SCROLL_DELAY = 2000

  // ---------------------------------------------------------------------------
  // 2. Systems
  // ---------------------------------------------------------------------------

  const build = () => {
    const els = document.querySelectorAll(SELECTOR)
    if (!els.length) return

    let i = 0
    for (const el of els) {
      i++
      const a = document.createElement('a')
      a.id          = `mark-${i}`
      a.href        = `#mark-${i}`
      a.textContent = i
      a.className   = 'line-mark'
      el.appendChild(a)
    }
  }

  const scrollToHash = () => {
    const hash = location.hash
    if (!hash.startsWith('#mark')) return
    document.querySelector(hash)?.scrollIntoView()
  }

  // ---------------------------------------------------------------------------
  // 3. Boot
  // ---------------------------------------------------------------------------

  const boot = () => {
    build()
    if (location.hash.startsWith('#mark')) setTimeout(scrollToHash, SCROLL_DELAY)
  }

  return { boot }
})()

LineMarkSystem.boot()
