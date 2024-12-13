'use strict'

/**
 * Gestion des onglets d'accordéon avec enregistrement des états en localStorage.
 */
const accordion = () => {
  const slug = window.location.pathname

  /**
   * Récupère l'état actuel des accordéons depuis localStorage
   * @returns {Object} L'objet d'état des accordéons
   */
  const getAccordionsState = () => {
    const storedState = localStorage.getItem('accordionsState')
    return storedState ? JSON.parse(storedState) : { accordionsState: {} }
  }

  /**
   * Met à jour l'état des accordéons dans localStorage
   * @param {Object} updatedState - Le nouvel état des accordéons
   */
  const updateAccordionsState = updatedState => {
    localStorage.setItem('accordionsState', JSON.stringify(updatedState))
  }

  const transformHTML = (() => {
    document.querySelectorAll('.accordion').forEach((accordion, i) => {
      accordion.id = `accordion-${i}`
      accordion.role = 'tablist'
      if (accordion.children[0].hasAttribute('name')) {
        accordion.setAttribute('data-singletab', 'true')
      }
    })

    document.querySelectorAll('.accordion > details').forEach((details, i) => {
      const accordionsState = getAccordionsState()
      const pageState = accordionsState.accordionsState[slug] || {}
      
      // Priorité à l'état localStorage sur l'attribut 'open'
      const dataOpen = pageState[`accordion-${i}`] === 'open' 
        ? 'true' 
        : (pageState[`accordion-${i}`] === 'close' 
          ? 'false' 
          : (details.hasAttribute('open') ? 'true' : 'false'))

      details.outerHTML = `<div id="accordion-details-${i}" class="accordion-details" data-open="${dataOpen}">${details.innerHTML}</div>`
    })

    document.querySelectorAll('.accordion > * > summary').forEach((summary, i) => {
      const ariaExpanded = summary.parentElement.dataset.open === 'true' ? 'true' : 'false'
      summary.outerHTML = `<button id="accordion-summary-${i}" type="button" class="accordion-summary" role="tab" aria-controls="accordion-panel-${i}" aria-expanded="${ariaExpanded}">${summary.innerHTML}</button>`
    })

    document.querySelectorAll('.accordion > * > :last-child').forEach((panel, i) => {
      panel.id = `accordion-panel-${i}`
      panel.classList.add('accordion-panel')
      panel.role = 'tabpanel'
      panel.setAttribute('aria-labelledby', `accordion-summary-${i}`)
      panel.ariaHidden = panel.parentElement.dataset.open === 'true' ? 'false' : 'true'
    })
  })()

  const stateManagement = (() => {
    document.querySelectorAll('.accordion-summary').forEach((summary, i) => {
      summary.addEventListener('click', () => {
        const details = summary.parentElement
        const singleTabOption = details.parentElement.dataset.singletab
        const panel = summary.nextElementSibling
        const accordionsState = getAccordionsState()

        if (!accordionsState.accordionsState[slug]) {
          accordionsState.accordionsState[slug] = {}
        }

        details.dataset.open = details.dataset.open === 'true' ? 'false' : 'true'

        if (details.dataset.open === 'true') {
          summary.ariaExpanded = 'true'
          accordionsState.accordionsState[slug][`accordion-${i}`] = 'open'
          openedPanel(panel)
        } else {
          summary.ariaExpanded = 'false'
          accordionsState.accordionsState[slug][`accordion-${i}`] = 'close'
          closedPanel(panel)
        }

        updateAccordionsState(accordionsState)

        if (singleTabOption) siblingStateManagement(details, accordionsState)
      })
    })
  })()

  const openedPanel = panel => {
    panel.style.maxHeight = `${panel.scrollHeight}px`
    panel.addEventListener('transitionend', () => panel.removeAttribute('style'))
    panel.ariaHidden = 'false'
  }

  const closedPanel = panel => {
    panel.style.maxHeight = `${panel.scrollHeight}px`
    requestAnimationFrame(() => {
      panel.removeAttribute('style')
      panel.ariaHidden = 'true'
    })
  }

  const siblingStateManagement = (details, accordionsState) => {
    for (const sibling of details.parentElement.children) {
      if (sibling !== details) {
        sibling.dataset.open = 'false'
        sibling.firstElementChild.ariaExpanded = 'false'
        closedPanel(sibling.lastElementChild)

        const siblingIndex = sibling.id.match(/\d+$/i)[0]
        accordionsState.accordionsState[slug][`accordion-${siblingIndex}`] = 'close'
      }
    }

    updateAccordionsState(accordionsState)
  }
}

window.addEventListener('DOMContentLoaded', accordion())