/**
 * @summary Active la classe CSS `start` sur les éléments `.target-is-visible`
 * à leur entrée dans le viewport.
 *
 * @strategy
 * - Collecte AOT des cibles à l'initialisation : un seul `querySelectorAll`,
 *   aucune requête DOM répétée au runtime.
 * - Pattern one-shot : `unobserve` immédiat après déclenchement.
 *   Zéro overhead post-activation, aucun listener résiduel.
 * - Aucun polling, aucun listener `scroll` : délégation complète
 *   au moteur d'intersection natif du navigateur.
 *
 * @architectural-decision
 * - `threshold: 0.5` — seuil UX délibéré (50 % visible avant activation).
 *   À réviser si les animations doivent démarrer plus tôt (`0`) ou exiger
 *   une visibilité totale (`1`).
 * - Classe `start` et non `active` : nomenclature orientée déclenchement
 *   d'animation. `active` est ambigu avec les états interactifs (hover, focus).
 *   Ce choix est un contrat CSS : toute modification impose une mise à jour
 *   des keyframes associées.
 * - Pas de garde `DOMContentLoaded` : suppose un chargement différé (`defer`)
 *   ou une position en fin de `<body>`. Si ce contrat change, la garde devient
 *   nécessaire.
 */

/*
function activateOnScroll() {
  const targetElements = document.querySelectorAll('.target-is-visible')

  if (!targetElements.length) return

  const observer = new IntersectionObserver((entries, observer) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('start')
        observer.unobserve(entry.target)
      }
    }
  }, {
    root: null,
    rootMargin: '0px',
    threshold: 0.5,
  })

  for (const element of targetElements) {
    observer.observe(element)
  }
}

activateOnScroll()
*/
