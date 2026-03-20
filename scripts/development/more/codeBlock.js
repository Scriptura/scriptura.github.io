'use strict'

/**
 * @summary Initialise les blocs de code : bouton copy-to-clipboard et bandeau
 * de langue. Cible les éléments `.pre > code` et `.pre` présents au moment
 * de l'exécution.
 *
 * @strategy
 * - AOT : collecte unique des cibles DOM via `querySelectorAll` à
 *   l'initialisation. Aucune requête répétée au runtime.
 * - Batch read/write : toutes les lectures de layout (`offsetHeight`) sont
 *   collectées avant toute mutation DOM, évitant N reflows en boucle.
 * - Fonctions nommées plutôt qu'IIFE assignées à `const` : le retour `undefined`
 *   d'une IIFE de setup n'apporte rien ; la fonction nommée est plus lisible
 *   et produit des stack traces exploitables.
 * - `selectText` réduit à la seule branche `getSelection` (standard W3C).
 *   La branche `createTextRange` (IE < 9) est supprimée — IE est hors support
 *   depuis 2022, la dette ne justifie plus le code mort.
 *
 * @architectural-decision
 * - `offsetHeight < 30` : heuristique visuelle pour les blocs mono-ligne,
 *   déterminée à runtime faute de signal statique (data-attribute CMS ou
 *   classe AOT). Si un signal statique devient disponible côté build/CMS,
 *   supprimer cette lecture de layout et la remplacer par un data-attribute.
 * - `injectSvgSprite` : fonction externe supposée disponible globalement au
 *   moment de l'exécution. Contrat non formalisé. Un guard `typeof` protège
 *   le script mais ne résout pas la dépendance implicite — à externaliser
 *   dans un module si l'architecture évolue vers ESM.
 * - `document.execCommand('copy')` conservé comme fallback déprécié.
 *   À supprimer dès que le support ciblé le permet.
 * - Pas de `DOMContentLoaded` : suppose exécution différée (`defer`) ou
 *   position en fin de `<body>`. Si ce contrat change, la garde devient
 *   nécessaire.
 */

const selectText = node => {
  if (!window.getSelection) {
    console.warn('selectText: API getSelection non supportée.')
    return
  }
  const selection = window.getSelection()
  const range = document.createRange()
  range.selectNodeContents(node)
  selection.removeAllRanges()
  selection.addRange(range)
}

function initCopyButtons() {
  const codeElements = document.querySelectorAll('.pre > code:not(:empty)')
  if (!codeElements.length) return

  // Batch read — toutes les lectures layout avant toute écriture DOM
  const heights = Array.from(codeElements, el => el.offsetHeight)

  for (let i = 0; i < codeElements.length; i++) {
    const el = codeElements[i]
    const label = el.dataset.select || 'Select and copy'
    const button = document.createElement('button')

    button.type = 'button'
    button.title = label
    button.ariaLabel = label

    if (heights[i] < 30) button.classList.add('copy-offset')

    if (typeof injectSvgSprite === 'function') injectSvgSprite(button, 'copy')

    button.addEventListener('click', () => {
      selectText(el)
      if (navigator.clipboard) {
        navigator.clipboard.writeText(el.textContent)
      } else {
        document.execCommand('copy')
      }
    })

    el.parentElement.appendChild(button)
  }
}

function initCodeBlockTitles() {
  const blocks = document.querySelectorAll('.pre')
  if (!blocks.length) return

  for (const el of blocks) {
    const firstChild = el.children[0]
    if (!firstChild) continue

    const language = firstChild.dataset.language
    const item = document.createElement('div')

    if (typeof injectSvgSprite === 'function') injectSvgSprite(item, 'code')

    if (language) {
      const span = document.createElement('span')
      span.textContent = language
      item.appendChild(span)
    }

    el.appendChild(item)
  }
}

initCopyButtons()
initCodeBlockTitles()
