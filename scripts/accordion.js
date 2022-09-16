'use strict'

// @documentation :
// Le html d'origine est composée de details > summary + div :
//.accordion
//  details
//    summary Title item
//    div Content item
// La première partie du script transforme ce code impossible à animer en divs, en récupérant les attributs de leur état d'origine (ouvert/fermé) :
//.accordion
//  .accordion-details
//    .accordion-summary Title item
//    .accordion-content Content item
// La deuxième partie du code concerne les changements d'états des onglets/panneaux (ouvert/fermé).

// @params, deux options :
// @option 'open' : onglet ouvert par défaut ; à définir sur l'élément <details> via l'attribut 'open' (comportement html natif)
// @option 'singleTab' : un seul onglet s'ouvre à la fois ; à définir sur la div.accordion via l'attribut data-singletab

// 1. Option 'open'
// 2. Option 'singleTab'

// Inspiration pour les rôles et les attributs aria :
// @see https://www.w3.org/TR/wai-aria-practices-1.1/examples/accordion/accordion.html
// @see https://jqueryui.com/accordion/
// @see http://accessibility.athena-ict.com/aria/examples/tabpanel2.shtml

const accordion = (() => {
  document.querySelectorAll('.accordion').forEach(e => e.setAttribute('role', 'tablist'))
  const transformationOfDetails = (() => {
    document.querySelectorAll('.accordion > details').forEach(details => {
      const html = details.innerHTML,
            substitute = document.createElement('div')
      substitute.classList.add('accordion-details')
      if (details.open) {
        substitute.classList.add('open') // 1
      }
      details.after(substitute, details)
      substitute.appendChild(details).insertAdjacentHTML('afterend', html)
      details.parentElement.removeChild(details)
    })
 })()
  const transformationOfSummarys = (() => {
    let i = 0
    document.querySelectorAll('.accordion > * > summary').forEach(summary => {
      i++
      const html = summary.innerHTML,
            substitute = document.createElement('button')
      substitute.id = 'accordion-summary-' + i
      substitute.type = 'button'
      substitute.classList.add('accordion-summary')
      substitute.setAttribute('role', 'tab')
      substitute.setAttribute('aria-controls', 'accordion-panel-' + i)
      summary.after(substitute, summary)
      substitute.appendChild(summary).insertAdjacentHTML('afterend', html)
      summary.parentElement.removeChild(summary)
    })
  })()
  const transformationOfPannels = (() => {
    let i = 0
    document.querySelectorAll('.accordion > * > :last-child').forEach(panel => {
      i++
      panel.id = 'accordion-panel-' + i
      panel.classList.add('accordion-panel')
      panel.setAttribute('role', 'tabpanel')
      panel.setAttribute('aria-labelledby', 'accordion-summary-' + i)
    })
  })()
  const stateManagement = (() => {
    document.querySelectorAll('.accordion-details').forEach(details => {
      const accordionSummary = details.children[0],
            accordionPanel = details.children[1]
      if (details.classList.contains('open')) {
        accordionSummary.setAttribute('aria-expanded', 'true')
        accordionPanel.style.maxHeight = accordionPanel.scrollHeight + 'px'
        //window.onresize = () => accordionPanel.style.maxHeight = accordionPanel.scrollHeight + 'px' //...
        accordionPanel.setAttribute('aria-hidden', 'false')
      }
      else {
        accordionSummary.setAttribute('aria-expanded', 'false')
        accordionPanel.setAttribute('aria-hidden', 'true')
      }
    })
    document.querySelectorAll('.accordion-summary').forEach(accordionSummary => {
      accordionSummary.addEventListener('click', () => {
        const singleTab = accordionSummary.parentElement.parentElement.dataset.singletab // 2
        accordionSummary.parentElement.classList.toggle('open')
        if (accordionSummary.parentElement.classList.contains('open'))
          accordionSummary.setAttribute('aria-expanded', 'true')
        else
          accordionSummary.setAttribute('aria-expanded', 'false')
        if (singleTab) siblingStateManagement(accordionSummary.parentElement)
        const accordionPanel = accordionSummary.nextElementSibling
        //accordionPanel.addEventListener('click', () =>  accordionPanel.style.maxHeight = accordionPanel.scrollHeight + 'px') //... <<<<<<<<
        if (accordionPanel.getAttribute('aria-hidden') === 'false') {
          accordionPanel.style.maxHeight = null
          accordionPanel.setAttribute('aria-hidden', 'true')
          //accordionPanel.ontransitionend = () => accordionPanel.style.display = 'none'
        }
        else {
          //accordionPanel.style.display = 'block' //...
          accordionPanel.style.maxHeight = accordionPanel.scrollHeight + 'px'
          accordionPanel.setAttribute('aria-hidden', 'false')
        }
      })
    })
  })()
  const siblingStateManagement = el => {
    for (const sibling of el.parentElement.children) {
      if (sibling !== el) {
        sibling.classList.remove('open')
        sibling.firstElementChild.setAttribute('aria-expanded', 'false')
        sibling.lastElementChild.setAttribute('aria-hidden', 'true')
        sibling.lastElementChild.style.maxHeight = null
      }
    }
  }
})()
