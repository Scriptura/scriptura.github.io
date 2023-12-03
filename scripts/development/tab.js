'use strict'

const tabs = () => {

  const slug = window.location.pathname,
        tabsPanel = `${(slug.substring(0, slug.lastIndexOf('.')) || slug).replace(/[\W_]/gi, '').toLowerCase()}TabsPanel`

  const setCurrentTab = tab => {
    tab.disabled = true
    tab.classList.add('current')
    tab.ariaSelected = 'true'
  }

  const setPastTab = tab => {
    tab.disabled = false
    tab.classList.remove('current')
    tab.ariaSelected = 'false'
  }

  const transformHTML = (tabs => {

    const tabList = document.createElement('div')
    
    tabList.classList.add('tab-list')
    tabList.role = 'tablist'
    tabList.ariaLabel = 'Entertainment'

    tabs.forEach((tabs, i) => {
      tabs.id = `tabs-${i}`
      tabs.prepend(tabList)
    })

    document.querySelectorAll('.tabs > * > summary').forEach((summary, i) => {
      const tablist = summary.parentElement.parentElement.firstElementChild

      tablist.appendChild(summary)
      summary.outerHTML = `<button id="tabsummary-${i}" type="button" class="tab-summary" role="tab" aria-controls="tab-panel-${i}" aria-expanded="false">${summary.innerHTML}</button>`
    })

    document.querySelectorAll('.tabs > details > *').forEach((panel, i) => {
      panel.parentElement.parentElement.appendChild(panel)
      panel.parentElement.querySelector('details').remove()
      panel.outerHTML = `<div id="tab-panel-${i}" class="tab-panel" role="tabpanel" ariaLabelledby="tabsummary-${i}">${panel.innerHTML}</div>`
    })

    document.querySelectorAll('.tab-summary:first-child').forEach(firstTab => setCurrentTab(firstTab))

  })(document.querySelectorAll('.tabs'))

  const stateManagement = (() => {

    document.querySelectorAll('.tab-summary').forEach((tab) => {

      const currentPanel = document.getElementById(tab.getAttribute('aria-controls'))

      tab.addEventListener('click', () => {
        setCurrentTab(tab)
        localStorage.setItem(tabsPanel + tab.id.match(/[0-9]$/i)[0], 'open')
        currentPanel.ariaHidden = 'false'
        tab.parentElement.parentElement.querySelectorAll('.tab-panel').forEach(panel => {
          if (panel !== currentPanel) {
            if (panel.parentElement === tab.parentElement.parentElement) panel.ariaHidden = 'true'
            if (tab === tab.classList.contains('open')) tab.classList.remove('open')
          }
        })
        siblingStateManagement(tab)
      })

    })
    
  })()

  const siblingStateManagement = tab => {
    [...tab.parentElement.children].forEach(tabSibling => {
      if (tabSibling !== tab) {
        setPastTab(tabSibling)
        localStorage.setItem(tabsPanel + tabSibling.id.match(/[0-9]$/i)[0], 'close')
      }
    })
  }

}

window.addEventListener('DOMContentLoaded', tabs()) // @note S'assurer que le script est bien chargé après le DOM et ce quelque soit la manière dont il est appelé.
