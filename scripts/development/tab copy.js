'use strict'

const tabs = () => {
  const slug = window.location.pathname,
    tabsPanel = `${
      (slug.substring(0, slug.lastIndexOf('.')) || slug).replace(
        /[\W_]/gi,
        '',
      ) || 'index'.toLowerCase()
    }TabsPanel` // @note Création d'un nom de variable à partir du slug de l'URL.

  const transformHTML = () => {
    document.querySelectorAll('.tabs').forEach((tabs, i) => {
      // @note Création d'un panneau pour contenir les boutons/onglets
      tabs.id = `tabs-${i}`
      tabs.insertAdjacentHTML(
        'afterbegin',
        `<div role="tablist" aria-label="Entertainment" class="tab-list"></div>`,
      )
    })

    document.querySelectorAll('.tabs > * > summary').forEach((summary, i) => {
      //const stateAria = localStorage.getItem(tabsPanel + i) === 'open' ? 'true' : 'false'
      summary.parentElement.parentElement.firstElementChild.appendChild(summary) // @note Déplacement de <summary> dans "div.tab-list"
      //summary.outerHTML = `<button id="tabsummary-${i}" type="button" role="tab" class="tab-summary" aria-controls="tab-panel-${i}" aria-selected="${stateAria}" aria-expanded="${stateAria}">${summary.innerHTML}</button>`
      summary.outerHTML = `<button id="tabsummary-${i}" type="button" role="tab" class="tab-summary" aria-controls="tab-panel-${i}" aria-selected="false" aria-expanded="false">${summary.innerHTML}</button>`
    })

    document.querySelectorAll('.tab-summary:first-child').forEach(firstTab => {
      setCurrentTab(firstTab)
      //if (!localStorage.getItem(tabsPanel + i) || localStorage.getItem(tabsPanel + i) === 'open') setCurrentTab(firstTab)
      //else setPastTab(firstTab)
    })

    document.querySelectorAll('.tabs > details > *').forEach((panel, i) => {
      panel.id = `tab-panel-${i}`
      panel.classList.add('tab-panel')
      panel.role = 'tabpanel'
      panel.ariaHidden = 'true'
      panel.setAttribute('aria-labelledby', `tabsummary-${i}`) // @note Pas de notation par point possible pour cet attribut car non supporté par JavaScript pour l'instant @todo À réévaluer dans le temps.
      panel.parentElement.parentElement.appendChild(panel)
      panel.parentElement.children[1].remove() // @note Remove <details>.
    })

    document
      .querySelectorAll('.tabs > :nth-child(2)')
      .forEach(firstPanel => (firstPanel.ariaHidden = 'false'))
  }

  const stateManagement = () => {
    document.querySelectorAll('.tab-summary').forEach(tab => {
      const currentPanel = document.getElementById(
        tab.getAttribute('aria-controls'),
      )

      tab.addEventListener('click', () => {
        setCurrentTab(tab)
        localStorage.setItem(tabsPanel + tab.id.match(/\d+$/i)[0], 'open')
        currentPanel.ariaHidden = 'false'
        tab.parentElement.parentElement
          .querySelectorAll(':scope > .tab-panel')
          .forEach(
            panel =>
              (panel.ariaHidden = panel !== currentPanel ? 'true' : 'false'),
          )
        siblingStateManagement(tab)
      })
    })
  }

  const siblingStateManagement = tab => {
    ;[...tab.parentElement.children].forEach(tabSibling => {
      if (tabSibling !== tab) {
        setPastTab(tabSibling)
        localStorage.setItem(
          tabsPanel + tabSibling.id.match(/\d+$/i)[0],
          'close',
        )
      }
    })
  }

  const setCurrentTab = tab => {
    tab.disabled = true
    tab.ariaSelected = 'true'
    tab.ariaExpanded = 'true'
  }

  const setPastTab = tab => {
    tab.disabled = false
    tab.ariaSelected = 'false'
    tab.ariaExpanded = 'false'
  }

  transformHTML()
  stateManagement()
}

window.addEventListener('DOMContentLoaded', tabs()) // @note S'assurer que le script est bien chargé après le DOM et ce quelque soit la manière dont il est appelé.
