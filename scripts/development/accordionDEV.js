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

  const accordions = document.querySelectorAll('.accordion')

  const replaceHTML = (accordion, i) => {
    accordion.id = `accordion-${i}`
    accordion.setAttribute('role', 'tablist')
    replaceDetailss(accordion.children)
  }

  const replaceDetailss = detailss => {
    let i = 0
    for (const details of detailss) {
      i++
      const html = details.innerHTML,
            substitute = document.createElement('div')
            
      substitute.classList.add('accordion-details')
      if (details.open) substitute.classList.add('open') // 1
      details.after(substitute, details)
      substitute.appendChild(details).insertAdjacentHTML('afterend', html)
      details.parentElement.removeChild(details)
      replaceSummary(details.firstElementChild, i)
    }
  }

  //const replaceSummary = (summary, i) => summary.outerHTML = `<button id="accordion-summary-${i}" type="button" class="accordion-summary" role="tab" aria-controls="accordion-panel-${i}" aria-expanded="false">${summary.innerHTML}</button>`

  const replaceSummary = (summary, i) => {
    summary.outerHTML = `<button id="accordion-summary-${i}" type="button" class="accordion-summary" role="tab" aria-controls="accordion-panel-${i}" aria-expanded="false">${summary.innerHTML}</button>`
  }

  const init = () => {
    let i = 0
    for (const accordion of accordions) {
      i++
      replaceHTML(accordion, i)
    }
  }

  init()

}

window.addEventListener('DOMContentLoaded', accordion()) // @note S'assurer que le script est bien chargé après le DOM et ce quelque soit la manière dont il est appelé.
