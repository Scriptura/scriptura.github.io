'use strict'

/**
 * Initialise le comportement des onglets sur la page.
 * Cette fonction configure les onglets, leur gestion d'état et
 * conserve les états des onglets en mémoire dans un format JSON.
 * @function
 * @returns {void}
 */
const tabs = () => {
  const slug = window.location.pathname

  /**
   * Récupère l'état actuel des onglets depuis localStorage
   * @returns {Object} L'objet d'état des onglets
   */
  const getTabsState = () => {
    const storedState = localStorage.getItem('tabsState')
    return storedState ? JSON.parse(storedState) : { tabsState: {} }
  }

  /**
   * Met à jour l'état des onglets dans localStorage
   * @param {Object} updatedState - Le nouvel état des onglets
   */
  const updateTabsState = updatedState => {
    localStorage.setItem('tabsState', JSON.stringify(updatedState))
  }

  const transformHTML = () => {
    document.querySelectorAll('.tabs').forEach((tabs, i) => {
      tabs.id = `tabs-${i}`
      tabs.insertAdjacentHTML('afterbegin', `<div role="tablist" aria-label="Entertainment" class="tab-list"></div>`)
    })

    document.querySelectorAll('.tabs > * > summary').forEach((summary, i) => {
      const tabsState = getTabsState()
      const pageState = tabsState.tabsState[slug] || {}
      const state = pageState[`tab-${i}`] === 'open'

      const summaryHtml = summary.innerHTML
      summary.parentElement.parentElement.firstElementChild.appendChild(summary)
      summary.outerHTML = `<button id="tabsummary-${i}" type="button" role="tab" class="tab-summary" aria-controls="tab-panel-${i}" aria-selected="${state}" aria-expanded="${state}" ${
        state ? 'disabled' : ''
      }>${summaryHtml}</button>`
    })

    document.querySelectorAll('.tab-summary:first-child').forEach(firstTab => setCurrentTab(firstTab))

    document.querySelectorAll('.tabs > details > *').forEach((panel, i) => {
      panel.id = `tab-panel-${i}`
      panel.classList.add('tab-panel')
      panel.role = 'tabpanel'
      panel.setAttribute('aria-labelledby', `tabsummary-${i}`)
      panel.ariaHidden = 'true'
      panel.parentElement.parentElement.appendChild(panel)
      panel.parentElement.children[1].remove()
    })

    document.querySelectorAll('.tabs > :nth-child(2)').forEach(firstPanel => (firstPanel.ariaHidden = 'false'))
  }

  const stateManagement = () => {
    document.querySelectorAll('.tab-summary').forEach(tab => {
      tab.addEventListener('click', () => handleTabClick(tab))
    })
  }

  const handleTabClick = tab => {
    const tabIndex = tab.id.match(/\d+$/i)[0]
    const currentPanel = document.getElementById(tab.getAttribute('aria-controls'))

    setCurrentTab(tab)

    // Mise à jour de l'état dans le localStorage
    const tabsState = getTabsState()
    if (!tabsState.tabsState[slug]) {
      tabsState.tabsState[slug] = {}
    }
    tabsState.tabsState[slug][`tab-${tabIndex}`] = 'open'
    updateTabsState(tabsState)

    currentPanel.ariaHidden = 'false'

    const parentElement = tab.parentElement.parentElement
    parentElement.querySelectorAll(':scope > .tab-panel').forEach(panel => {
      if (panel !== currentPanel) {
        panel.ariaHidden = 'true'
      }
    })

    siblingStateManagement(tab)
  }

  const siblingStateManagement = tab => {
    const tabsState = getTabsState()
    if (!tabsState.tabsState[slug]) {
      tabsState.tabsState[slug] = {}
    }

    const tabs = tab.parentElement.children
    ;[...tabs].forEach(tabSibling => {
      if (tabSibling !== tab) {
        setPastTab(tabSibling)
        const tabIndex = tabSibling.id.match(/\d+$/i)[0]
        tabsState.tabsState[slug][`tab-${tabIndex}`] = 'close'
      }
    })

    updateTabsState(tabsState)
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

  const restoreTabStates = () => {
    const tabsState = getTabsState()
    const pageState = tabsState.tabsState[slug] || {}

    document.querySelectorAll('.tab-summary').forEach(tab => {
      const tabIndexMatch = tab.id.match(/\d+$/i)
      if (!tabIndexMatch) return
      const tabIndex = tabIndexMatch[0]
      const state = pageState[`tab-${tabIndex}`]

      if (!state) return

      const panelId = `tab-panel-${tabIndex}`
      const panel = document.getElementById(panelId)

      if (panel) {
        panel.setAttribute('aria-hidden', state === 'open' ? 'false' : 'true')
      }

      const setTabState = state === 'open' ? setCurrentTab : setPastTab
      setTabState(tab)
    })
  }

  transformHTML()
  stateManagement()
  restoreTabStates()
}

window.addEventListener('DOMContentLoaded', tabs())
