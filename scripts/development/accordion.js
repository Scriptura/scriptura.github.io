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
      i++
      accordion.id = `accordion-${i}`
      accordion.role = 'tablist'
    })

    document.querySelectorAll('.accordion > details').forEach((details, i) => {
      i++
      let open
      details.open ? open = ' open' : open = '' // 1
      details.outerHTML = `<div id="accordion-details-${i}" class="accordion-details${open}">${details.innerHTML}</div>`
    })

    document.querySelectorAll('.accordion > * > summary').forEach((summary, i) => {
      i++
      summary.outerHTML = `<button id="accordion-summary-${i}" type="button" class="accordion-summary" role="tab" aria-controls="accordion-panel-${i}" aria-expanded="false">${summary.innerHTML}</button>`
    })

    document.querySelectorAll('.accordion > * > :last-child').forEach((panel, i) => {
      // @note On peut surcharger l'élément avec des attributs, mais il ne faut en aucun cas le remplacer pour éviter une animation d'ouverture si panneau ouvert par défaut.
      i++
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
        panel.style.maxHeight = panel.scrollHeight + 'px'
        summary.ariaExpanded = 'true'
        panel.ariaHidden = 'false'
      }
      else {
        summary.ariaExpanded = 'false'
        panel.ariaHidden = 'true'
      }
    })

    document.querySelectorAll('.accordion-summary').forEach(summary => {
      summary.addEventListener('click', () => {
        const singleTabOption = summary.parentElement.parentElement.dataset.singletab, // 2
              panel = summary.nextElementSibling
        summary.parentElement.classList.toggle('open')
        summary.parentElement.classList.contains('open') ? summary.ariaExpanded = 'true' : summary.ariaExpanded = 'false'
        if (singleTabOption) siblingStateManagement(summary.parentElement)
        if (panel.ariaHidden === 'false') {
          panel.removeAttribute('style')
          panel.ariaHidden = 'true'
        }
        else {
          panel.style.maxHeight = panel.scrollHeight + 'px'
          panel.ariaHidden = 'false'
        }
        //panel.addEventListener('transitionend', () => panel.removeAttribute('style'))
      })
    })

  })()

  const siblingStateManagement = el => {
    for (const sibling of el.parentElement.children) {
      if (sibling !== el) {
        sibling.classList.remove('open')
        sibling.firstElementChild.ariaExpanded = 'false'
        sibling.lastElementChild.ariaHidden = 'true'
        sibling.lastElementChild.removeAttribute('style') //sibling.lastElementChild.style.maxHeight = null
      }
    }
  }

}

window.addEventListener('DOMContentLoaded', accordion()) // @note S'assurer que le script est bien chargé après le DOM et ce quelque soit la manière dont il est appelé.
