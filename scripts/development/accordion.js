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

const accordion = (() => {

  document.querySelectorAll('.accordion').forEach(e => e.setAttribute('role', 'tablist'))

  const transformDetails = (() => {
    document.querySelectorAll('.accordion > details').forEach(details => {
      const html = details.innerHTML,
            substitute = document.createElement('div')
      substitute.classList.add('accordion-details')
      if (details.open) substitute.classList.add('open') // 1
      details.after(substitute, details)
      substitute.appendChild(details).insertAdjacentHTML('afterend', html)
      details.parentElement.removeChild(details)
    })
  })()

  const transformSummary = (() => {
    document.querySelectorAll('.accordion > * > summary').forEach((summary, i) => {
      i++
      const html = summary.innerHTML,
            substitute = document.createElement('button')
      substitute.id = 'accordion-summary-' + i
      substitute.type = 'button'
      substitute.classList.add('accordion-summary')
      substitute.role = 'tab'
      substitute.ariaControls = 'accordion-panel-' + i
      summary.after(substitute, summary)
      substitute.appendChild(summary).insertAdjacentHTML('afterend', html)
      summary.parentElement.removeChild(summary)
    })
  })()

  const transformPannel = (() => {
    document.querySelectorAll('.accordion > * > :last-child').forEach((panel, i) => {
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
        summary.ariaExpanded = 'true'
        panel.style.maxHeight = panel.scrollHeight + 'px'
        panel.ariaHidden = 'false'
      }
      else {
        summary.ariaExpanded = 'false'
        panel.ariaHidden = 'true'
      }
    })

    document.querySelectorAll('.accordion-summary').forEach(summary => {
      summary.addEventListener('click', () => {
        const singleTab = summary.parentElement.parentElement.dataset.singletab // 2
        summary.parentElement.classList.toggle('open')
        summary.parentElement.classList.contains('open') ? summary.ariaExpanded = 'true' : summary.ariaExpanded = 'false'
        if (singleTab) siblingStateManagement(summary.parentElement)
        const panel = summary.nextElementSibling
        if (panel.ariaHidden === 'false') {
          panel.removeAttribute('style') //panel.style.maxHeight = null
          panel.ariaHidden = 'true'
        }
        else {
          panel.style.maxHeight = panel.scrollHeight + 'px'
          panel.ariaHidden = 'false'
        }
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

})()
