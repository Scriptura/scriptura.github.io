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

  const transformHTML = (() => {

    document.querySelectorAll('.tabs').forEach((tabs, i) => {
      const tabList = document.createElement('div')
      tabList.classList.add('tab-list')
      tabList.role = 'tablist'
      tabList.ariaLabel = 'Entertainment'
      tabs.id = `tabs-${i}`
      tabs.prepend(tabList)
    })

    document.querySelectorAll('.tabs > * > summary').forEach((summary, i) => {
      const tablist = summary.parentElement.parentElement.firstElementChild,
            summaryHtml = summary.innerHTML,
            tab = document.createElement('button')
      tab.id = `tabsummary-${i}`
      tab.type = 'button'
      tab.classList.add('tab-summary')
      tab.role = 'tab'
      tab.setAttribute('aria-controls', `tab-panel-${i}`) // @note Pas de notation par point possible pour cet attribut.
      tablist.appendChild(tab)
      tab.insertAdjacentHTML('beforeend', summaryHtml)
      summary.parentElement.removeChild(summary)
    })

    document.querySelectorAll('.tabs > details > *').forEach((panel, i) => {
      panel.id = `tab-panel-${i}`
      panel.classList.add('tab-panel')
      panel.role = 'tabpanel'
      panel.ariaLabelledby = `tabsummary-${i}`
      panel.parentElement.parentElement.appendChild(panel)
      panel.parentElement.querySelector('details').remove()
    })

    document.querySelectorAll('.tab-summary:first-child').forEach(firstTab => setCurrentTab(firstTab))

  })()

  const stateManagement = (() => {

    document.querySelectorAll('.tab-summary').forEach((tab) => {

      const currentPanel = document.getElementById(tab.getAttribute('aria-controls'))
      console.log(currentPanel)

      tab.addEventListener('click', () => {
        [...tab.parentElement.children].forEach(tabSibling => {
          setPastTab(tabSibling)
          localStorage.setItem(tabsPanel + tabSibling.id.match(/[0-9]$/i)[0], 'close')
        })
        setCurrentTab(tab)
        localStorage.setItem(tabsPanel + tab.id.match(/[0-9]$/i)[0], 'open')

        currentPanel.ariaHidden = 'false'
        tab.parentElement.parentElement.querySelectorAll('.tab-panel').forEach(panel => {
          if (panel !== currentPanel) {
            if (panel.parentElement === tab.parentElement.parentElement) panel.ariaHidden = 'true'
            if (tab === tab.classList.contains('open')) tab.classList.remove('open')
          }
        })

      })

    })
    
  })()

}

window.addEventListener('DOMContentLoaded', tabs()) // @note S'assurer que le script est bien chargé après le DOM et ce quelque soit la manière dont il est appelé.
