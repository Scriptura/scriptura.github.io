'use strict'

const tabsSystem = () => {
  const slug = window.location.pathname
  const STATE_KEY = 'tabsState'

  // --- Data Access Layer ---
  const getStoredState = () => {
    const stored = localStorage.getItem(STATE_KEY)
    return stored ? JSON.parse(stored) : { tabsState: {} }
  }

  const saveStoredState = (newState) => {
    localStorage.setItem(STATE_KEY, JSON.stringify(newState))
  }

  // --- Logic / Systems ---
  
  /**
   * Aligne l'UI sur un état donné pour un groupe d'onglets
   * @param {HTMLElement} activeTab - L'onglet qui doit être actif
   * @param {HTMLElement} container - Le conteneur parent .tabs
   */
  const syncGroupState = (activeTab, container) => {
    const targetPanelId = activeTab.getAttribute('aria-controls')
    const allTabs = container.querySelectorAll('[role="tab"]')
    const allPanels = container.querySelectorAll('.tab-panel')

    // Update Tabs (Linear Scan)
    allTabs.forEach(tab => {
      const isActive = (tab === activeTab)
      tab.disabled = isActive
      tab.setAttribute('aria-selected', isActive)
      tab.setAttribute('aria-expanded', isActive)
    })

    // Update Panels (Linear Scan)
    allPanels.forEach(panel => {
      panel.setAttribute('aria-hidden', panel.id !== targetPanelId)
    })

    // Persistence update
    updatePersistence(activeTab.id, allTabs)
  }

  const updatePersistence = (activeId, siblingTabs) => {
    const state = getStoredState()
    if (!state.tabsState[slug]) state.tabsState[slug] = {}

    // On marque l'actif comme 'open', les autres du même groupe comme 'close'
    siblingTabs.forEach(tab => {
      state.tabsState[slug][tab.id] = (tab.id === activeId) ? 'open' : 'close'
    })

    saveStoredState(state)
  }

  // --- Initialization ---

  const init = () => {
    const containers = document.querySelectorAll('.tabs')
    const globalState = getStoredState().tabsState[slug] || {}

    containers.forEach(container => {
      const tabs = container.querySelectorAll('[role="tab"]')
      let tabToActivate = tabs[0] // Default fallback

      // Restauration de l'état si présent dans le storage
      tabs.forEach(tab => {
        if (globalState[tab.id] === 'open') {
          tabToActivate = tab
        }
        
        // Attachment de l'event
        tab.addEventListener('click', () => syncGroupState(tab, container))
      })

      // Premier rendu (Warm-up)
      if (tabToActivate) {
        syncGroupState(tabToActivate, container)
      }
    })
  }

  init()
}

// Lancement au DOMReady
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', tabsSystem)
} else {
  tabsSystem()
}
