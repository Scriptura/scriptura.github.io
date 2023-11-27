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

  const transformHTML = (() => {

    document.querySelectorAll('.accordion').forEach((accordion, i) => {
      accordion.id = `accordion-${i}`
      accordion.role = 'tablist'
    })

    document.querySelectorAll('.accordion > details').forEach((details, i) => {
      let openClass = ''
      if (details.open) openClass = ' open' // 1
      //details.open || localStorage.getItem(`accordionOpen${window.location.href + i}`) === 'open' ? openClass = ' open' : openClass = '' // 1
      details.outerHTML = `<div id="accordion-details-${i}" class="accordion-details${openClass}">${details.innerHTML}</div>`
    })

    document.querySelectorAll('.accordion > * > summary').forEach((summary, i) => {
      summary.outerHTML = `<button id="accordion-summary-${i}" type="button" class="accordion-summary" role="tab" aria-controls="accordion-panel-${i}" aria-expanded="false">${summary.innerHTML}</button>`
    })

    /**
     * @note On peut surcharger l'élément avec des attributs, mais il ne faut en aucun cas le remplacer pour éviter une animation d'ouverture si panneau ouvert par défaut.
     */
    document.querySelectorAll('.accordion > * > :last-child').forEach((panel, i) => {
      panel.id = 'accordion-panel-' + i
      panel.classList.add('accordion-panel')
      panel.role = 'tabpanel'
      panel.ariaLabelledby = 'accordion-summary-' + i
    })

  })()

  const stateManagement = (() => {

    document.querySelectorAll('.accordion-details').forEach(details => {
      const summary = details.firstElementChild,
            panel = details.lastElementChild
      if (details.classList.contains('open')) {
        summary.ariaExpanded = 'true'
        panel.ariaHidden = 'false'
      }
      else {
        summary.ariaExpanded = 'false'
        panel.ariaHidden = 'true'
      }
    })

    document.querySelectorAll('.accordion-summary').forEach((summary) => { // (summary, i)
      summary.addEventListener('click', () => {
        const details = summary.parentElement,
              singleTabOption = details.parentElement.dataset.singletab, // 2
              panel = summary.nextElementSibling
              details.classList.toggle('open')
        //stateInlocalStorage(details.classList.contains('open'), i)
        details.classList.contains('open') ? summary.ariaExpanded = 'true' : summary.ariaExpanded = 'false'
        if (panel.ariaHidden === 'false') {
          closedPanel(panel)
        } else {
          openedPanel(panel)
        }
        panel.addEventListener('transitionend', () => panel.removeAttribute('style'))
        if (singleTabOption) siblingStateManagement(details)
      })
    })

  })()

  const siblingStateManagement = details => {
    //let i = 0
    for (const sibling of details.parentElement.children) {
      if (sibling !== details) {
        sibling.classList.remove('open')
        sibling.firstElementChild.ariaExpanded = 'false'
        closedPanel(sibling.lastElementChild)
        //localStorage.removeItem(`accordionOpen${window.location.href + i}`)
        //i++
      }
    }
  }

  const openedPanel = panel => {
    panel.style.maxHeight = panel.scrollHeight + 'px'
    panel.ariaHidden = 'false'
  }

  const closedPanel = panel => {
    // @note Redéfinition de la hauteur du panneau avant la suppression de cette même définition un laps de temps plus tard. Le laps de temps est minime mais suffisant pour être pris en compte par l'animation CSS.
    panel.style.maxHeight = panel.scrollHeight + 'px'
    setTimeout(() => {
      panel.removeAttribute('style')
      panel.ariaHidden = 'true'
      , 1
    })
  }
  /*
  const stateInlocalStorage = (openClass, i) => {
    if (openClass) localStorage.setItem(`accordionOpen${window.location.href + i}`, 'open')
    else localStorage.removeItem(`accordionOpen${window.location.href + i}`)
  }
  */
}

window.addEventListener('DOMContentLoaded', accordion()) // @note S'assurer que le script est bien chargé après le DOM et ce quelque soit la manière dont il est appelé.
