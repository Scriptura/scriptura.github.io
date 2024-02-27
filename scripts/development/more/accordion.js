'use strict'

/**
 * @documentation :
 * Le html d'origine est composée de details > summary + div :
 *.accordion
 *  details
 *    summary Title item
 *    div Content item
 * La première partie du script transforme ce code impossible à animer, en récupérant les attributs de leur état d'origine (ouvert/fermé) :
 *.accordion
 *  div.accordion-details
 *  button.accordion-summary Title item
 *  div.accordion-panel Content item
 * La deuxième partie du code concerne les changements d'états des onglets/panneaux (ouvert/fermé).
 *
 * @param, deux options :
 * @option 'open' : onglet ouvert par défaut ; à définir sur l'élément <details> via l'attribut 'open' (comportement html natif)
 * @option 'singleTab' : un seul onglet s'ouvre à la fois ; à définir sur la div.accordion via l'attribut data-singletab
 *
 * 1. Option 'open'
 * 2. Option 'singleTab'
 *
 * Inspiration pour les rôles et les attributs aria :
 * @see https://www.w3.org/WAI/ARIA/apg/patterns/accordion/examples/accordion/
 * @see https://jqueryui.com/accordion/
 * @see http://accessibility.athena-ict.com/aria/examples/tabpanel2.shtml
 *
 * Mes remerciement à Ostara pour la factorisation du code @see https://codepen.io/ostara/pen/BajdPOO
 * Discution sur Alsacréations @see https://forum.alsacreations.com/topic-5-87178-1-Resolu-Revue-de-code-pour-un-menu-accordeon.html
 */

const accordion = () => {
  const slug = window.location.pathname,
    accordionPanel = `${(slug.substring(0, slug.lastIndexOf('.')) || slug).replace(/[\W_]/gi, '') || 'index'.toLowerCase()}AccordionPanel` // @note Création d'un nom de variable à partir du slug de l'URL.

  const transformHTML = (() => {
    document.querySelectorAll('.accordion').forEach((accordion, i) => {
      accordion.id = `accordion-${i}`
      accordion.role = 'tablist'
    })

    document.querySelectorAll('.accordion > details').forEach((details, i) => {
      const dataOpen =
        (details.open || localStorage.getItem(accordionPanel + i) === 'open') && localStorage.getItem(accordionPanel + i) !== 'close'
          ? 'true'
          : 'false' // 1
      details.outerHTML = `<div id="accordion-details-${i}" class="accordion-details" data-open="${dataOpen}">${details.innerHTML}</div>`
    })

    document.querySelectorAll('.accordion > * > summary').forEach((summary, i) => {
      const ariaExpanded = summary.parentElement.dataset.open === 'true' ? 'true' : 'false'
      summary.outerHTML = `<button id="accordion-summary-${i}" type="button" class="accordion-summary" role="tab" aria-controls="accordion-panel-${i}" aria-expanded="${ariaExpanded}">${summary.innerHTML}</button>`
    })

    document.querySelectorAll('.accordion > * > :last-child').forEach((panel, i) => {
      // @note On peut surcharger l'élément avec des attributs, mais il ne faut en aucun cas le remplacer pour éviter une transition d'ouverture si panneau ouvert par défaut.
      panel.id = `accordion-panel-${i}`
      panel.classList.add('accordion-panel')
      panel.role = 'tabpanel'
      panel.setAttribute('aria-labelledby', `accordion-summary-${i}`) // @note Cet attribut ne supporte pas la notation par point.
      panel.ariaHidden = panel.parentElement.dataset.open === 'true' ? 'false' : 'true' //panel.parentElement.open
    })
  })()

  const stateManagement = (() => {
    document.querySelectorAll('.accordion-summary').forEach((summary, i) => {
      summary.addEventListener('click', () => {
        const details = summary.parentElement,
          singleTabOption = details.parentElement.dataset.singletab, // 2
          panel = summary.nextElementSibling
        details.dataset.open = details.dataset.open === 'true' ? 'false' : 'true'
        if (details.dataset.open === 'true') {
          summary.ariaExpanded = 'true'
          localStorage.setItem(accordionPanel + i, 'open')
          openedPanel(panel)
        } else {
          summary.ariaExpanded = 'false'
          localStorage.setItem(accordionPanel + i, 'close')
          closedPanel(panel)
        }
        if (singleTabOption) siblingStateManagement(details)
      })
    })
  })()

  const openedPanel = panel => {
    panel.style.maxHeight = `${panel.scrollHeight}px`
    panel.addEventListener('transitionend', () => panel.removeAttribute('style'))
    panel.ariaHidden = 'false'
  }

  const closedPanel = panel => {
    // @note Redéfinition de la hauteur du panneau avant la suppression de cette même définition un laps de temps plus tard. Le laps de temps est minime mais suffisant pour être pris en compte par la transition CSS.
    panel.style.maxHeight = `${panel.scrollHeight}px`
    setTimeout(() => {
      panel.removeAttribute('style')
      ;(panel.ariaHidden = 'true'), 1
    })
  }

  const siblingStateManagement = details => {
    for (const sibling of details.parentElement.children) {
      if (sibling !== details) {
        sibling.dataset.open = 'false'
        sibling.firstElementChild.ariaExpanded = 'false'
        closedPanel(sibling.lastElementChild)
        localStorage.setItem(accordionPanel + sibling.id.match(/\d+$/i)[0], 'close') // @note Récupération de l'ID du panneau frère par regex.
      }
    }
  }
}

window.addEventListener('DOMContentLoaded', accordion()) // @note S'assurer que le script est bien chargé après le DOM et ce quelque soit la manière dont il est appelé.
