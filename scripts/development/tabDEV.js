'use strict'

const tabs = () => {

  const slug = window.location.pathname,
        tabsPanel = `${(slug.substring(0, slug.lastIndexOf('.')) || slug).replace(/[\W_]/gi, '') || 'index'.toLowerCase()}TabsPanel` // @note Création d'un nom de variable à partir du slug de l'URL.

  const transformHTML = () => {

    document.querySelectorAll('.tabs').forEach((tabs, i) => { // @note Création d'un panneau pour contenir les boutons/onglets
      tabs.id = `tabs-${i}`
      tabs.insertAdjacentHTML('afterbegin', `<div role="tablist" aria-label="Entertainment" class="tab-list"></div>`)
    })

    document.querySelectorAll('.tabs > * > summary').forEach((summary, i) => {
      const stateAria = localStorage.getItem(tabsPanel + i) === 'open' ? 'true' : 'false'
      summary.parentElement.parentElement.firstElementChild.appendChild(summary) // @note Déplacement de <summary> dans "div.tab-list"
      summary.outerHTML = `<button id="tabsummary-${i}" type="button" role="tab" class="tab-summary" aria-controls="tab-panel-${i}" aria-selected="${stateAria}" aria-expanded="${stateAria}">${summary.innerHTML}</button>`
    })

    document.querySelectorAll('.tab-summary:first-child').forEach((firstTab, i) => {
      //setCurrentTab(firstTab)
      if (!localStorage.getItem(tabsPanel + i) || localStorage.getItem(tabsPanel + i) === 'open') setCurrentTab(firstTab)
      else setPastTab(firstTab)
      
    })

    document.querySelectorAll('.tabs > details > *').forEach((panel, i) => {
      panel.id = `tab-panel-${i}`
      panel.classList.add('tab-panel')
      panel.role = 'tabpanel'
      panel.setAttribute('aria-labelledby', `tabsummary-${i}`) // @note Pas de notation par point possible pour cet attribut.
      panel.parentElement.parentElement.appendChild(panel)
      panel.parentElement.children[1].remove() // @note Remove <details>.
      panel.ariaHidden = !localStorage.getItem(tabsPanel + i) ? 'false' : localStorage.getItem(tabsPanel + i) === 'open' ? 'false' : 'true'
    })

    document.querySelectorAll('.tabs > details > :first-child').forEach(firstPanel => {
      firstPanel.ariaHidden = 'false'
    }) // À revoir...

  }

  const stateManagement = () => {

    document.querySelectorAll('.tab-summary').forEach((tab) => {

      const currentPanel = document.getElementById(tab.getAttribute('aria-controls')) // @note Cette sélection spécifique, et non "aria-hidden", empêche d'impacter les panneaux imbriqués dans d'autres panneaux.

      tab.addEventListener('click', () => {
        setCurrentTab(tab)
        localStorage.setItem(tabsPanel + tab.id.match(/\d+$/i)[0], 'open')
        currentPanel.ariaHidden = 'false'
        tab.parentElement.parentElement.querySelectorAll('.tab-panel').forEach(panel => {
          if (panel !== currentPanel && panel.parentElement === tab.parentElement.parentElement) panel.ariaHidden = 'true' // @note La condition empêche d'impacter les panneaux imbriqués dans d'autres panneaux.
        })
        siblingStateManagement(tab)
      })

    })
    
  }

  const siblingStateManagement = tab => {
    [...tab.parentElement.children].forEach(tabSibling => {
      if (tabSibling !== tab) {
        setPastTab(tabSibling)
        localStorage.setItem(tabsPanel + tabSibling.id.match(/\d+$/i)[0], 'close')
      }
    })
  }

  const setCurrentTab = tab => {
    tab.disabled = true
    tab.classList.add('current')
    tab.ariaSelected = 'true'
    tab.ariaExpanded = 'true'
  }

  const setPastTab = tab => {
    tab.disabled = false
    tab.classList.remove('current')
    tab.ariaSelected = 'false'
    tab.ariaExpanded = 'false'
  }
  
  transformHTML()
  stateManagement()

}

window.addEventListener('DOMContentLoaded', tabs()) // @note S'assurer que le script est bien chargé après le DOM et ce quelque soit la manière dont il est appelé.
