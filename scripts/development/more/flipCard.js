'use strict'

const flipList = document.querySelectorAll('.flip')
let autoFlipTimeout, autoUnflipTimeout
let isAutoFlipping = true // Variable de contrôle

/**
 * Retourne automatiquement la première carte flip après 2 secondes
 * et la remet à son état initial après une autre seconde.
 */
const autoFlipFirstCard = () => {
  if (flipList.length > 0) {
    autoFlipTimeout = setTimeout(() => {
      flipList[0].classList.add('active')
      autoUnflipTimeout = setTimeout(() => {
        flipList[0].classList.remove('active')
        isAutoFlipping = false // Processus automatique terminé
      }, 2000)
    }, 2000)
  }
}

autoFlipFirstCard()

/**
 * Ajoute un gestionnaire d'événements à chaque élément avec la classe 'flip'.
 * Lorsqu'un élément est cliqué, il vérifie s'il possède déjà la classe 'active'.
 * Si c'est le cas, il la supprime, sinon il l'ajoute.
 * Si un autre élément a déjà la classe 'active', elle lui est retirée après 3 secondes.
 * @param {NodeList} flipList Liste des éléments auxquels ajouter des gestionnaires d'événements.
 */
flipList.forEach(flip => {
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
})
