'use strict'

// @note Marqueurs pour les pages article

const lineMarks = elements => {
  const els = document.querySelectorAll(elements)
  const lineMarksAdd = el => {
    const a = document.createElement('a')
    a.id = 'mark' + i
    a.setAttribute('href', '#mark' + i)
    const text = document.createTextNode(i)
    a.appendChild(text)
    a.classList.add('line-mark')
    el.appendChild(a)
  }
  let i = 0
  for (const el of els) {
    i++
    //if (i % 5 === 0) {}
    //el.classList.add('relative')
    lineMarksAdd(el)
  }
}

lineMarks(
  '.add-line-marks > :where(p, h2, h3, h4, h5, h6, blockquote, ul, ol, [class*=grid])',
) // @note Pour un meilleur contrôle il est préférable de définir explicitement les items plutôt que d'utiliser le sélecteur universel '*' et de procéder par exclusion.

/**
 * @description Si URL avec un hash, alors défilement jusqu'à l'ID cible.
 * @note Ce script double le comportement par défaut des navigateurs, se dernier se révélant défaillant sous Chrome, que ce soit pour les pages dotées d'un contenu conséquent ou en raison d'ancres créés en JavaScript après le chargement initial de la page (comme avec notre fonction lineMarks). Firefox ne souffre pas de ces limitations.
 * @note Supprime un comportement de chrome qui est de rester au même endroit d'une page si rechargement de la page. @todo À réévaluer dans le temps.
 * @note Limitation du scope aux ancres `#mark*`.
 */
const hash = window.location.hash
if (hash.substring(0, 5) === '#mark')
  window.addEventListener('load', () => {
    const scroll = () => document.querySelector(hash).scrollIntoView()
    //setTimeout(scroll, 2000) // @note Correction du fonctionnement après un laps de temps.
    scroll()
  })
