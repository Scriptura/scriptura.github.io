'use strict'

const flipList = document.querySelectorAll('.flip')
let autoFlipTimeout, autoUnflipTimeout
let isAutoFlipping = true // Variable de contrôle

/**
 * Script de démonstration permettant à l'utilisateur de comprendre qu'une action
 * est possible sur la carte. Retourne automatiquement la première carte après n seconde
 * et la remet à son état initial après n seconde.
 */
const autoFlipFirstCard = () => {
  if (flipList.length > 0) {
    autoFlipTimeout = setTimeout(() => {
      flipList[0].classList.add('active')
      autoUnflipTimeout = setTimeout(() => {
        flipList[0].classList.remove('active')
        isAutoFlipping = false // Processus automatique terminé
      }, 1500)
    }, 1000)
  }
}

/**
 * Gère l'événement de vue de page en mettant à jour le compteur de vues dans
 * le stockage local et en retournant automatiquement la première carte si le
 * compteur de vues est inférieur à n.
 *
 * @note Le compteur de vues est unique pour toutes les pages.
 */
const handlePageView = () => {
  const pageViewed = 'demoCounterFlipCards' // @note Un unique compteur pour toutes les pages.

  let views = parseInt(localStorage.getItem(pageViewed)) || 0
  views++
  localStorage.setItem(pageViewed, views)

  if (views < 4) {
    autoFlipFirstCard()
  }
}

handlePageView()

/**
 * Ajoute un gestionnaire d'événements à chaque élément avec la classe 'flip'.
 * Lorsqu'un élément est cliqué, il vérifie s'il possède déjà la classe 'active'.
 * Si c'est le cas, il la supprime, sinon il l'ajoute.
 * Si un autre élément a déjà la classe 'active', elle lui est retirée après 3 secondes.
 * @param {NodeList} flipList Liste des éléments auxquels ajouter des gestionnaires d'événements.
 */
flipList.forEach(flip => {
  flip.removeAttribute('tabindex')
  flip.addEventListener('click', () => {
    // Annuler le processus automatique si l'utilisateur clique sur la première carte flip
    if (flip === flipList[0] && isAutoFlipping) {
      clearTimeout(autoFlipTimeout)
      clearTimeout(autoUnflipTimeout)
      isAutoFlipping = false
    }

    if (flip.classList.contains('active')) {
      flip.classList.remove('active')
    } else {
      document.querySelectorAll('.flip').forEach(element => {
        if (element !== flip && element.classList.contains('active')) {
          setTimeout(() => {
            element.classList.remove('active')
          }, 3000)
        }
      })
      flip.classList.add('active')
    }
  })

  flip.addEventListener('focusin', () => {
    flip.classList.remove('active')
  })
})
