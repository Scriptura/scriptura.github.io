/**
 * Initialise le comportement des onglets sur la page.
 * Cette fonction configure les onglets, leur gestion d'état et
 * conserve les états des onglets en mémoire.
 * Elle transforme le HTML existant pour ajouter des fonctionnalités
 * d'onglets et gère l'état des onglets en fonction des interactions
 * de l'utilisateur, en gardant en mémoire les états précédents.
 * @function
 * @returns {void}
 */
const tabs = () => {
  const slug = window.location.pathname
  const tabsPanel = `${(slug.substring(0, slug.lastIndexOf('.')) || slug).replace(/[\W_]/gi, '') || 'index'.toLowerCase()}TabsPanel`

  const transformHTML = () => {
    document.querySelectorAll('.tabs').forEach((tabs, i) => {
      tabs.id = `tabs-${i}`
      tabs.insertAdjacentHTML('afterbegin', `<div role="tablist" aria-label="Entertainment" class="tab-list"></div>`)
    })

    document.querySelectorAll('.tabs > * > summary').forEach((summary, i) => {
      const state = localStorage.getItem(`${tabsPanel}${i}`) === 'open'
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
    localStorage.setItem(`${tabsPanel}${tabIndex}`, 'open')
    currentPanel.ariaHidden = 'false'

    const parentElement = tab.parentElement.parentElement
    parentElement.querySelectorAll('.tab-panel').forEach(panel => {
      if (panel !== currentPanel) {
        panel.ariaHidden = 'true'
      }
    })

    siblingStateManagement(tab)
  }

  const siblingStateManagement = tab => {
    const tabs = tab.parentElement.children
    ;[...tabs].forEach(tabSibling => {
      if (tabSibling !== tab) {
        setPastTab(tabSibling)
        const tabIndex = tabSibling.id.match(/\d+$/i)[0]
        localStorage.setItem(`${tabsPanel}${tabIndex}`, 'close')
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

  const restoreTabStates = () => {
    document.querySelectorAll('.tab-summary').forEach(tab => {
      const tabIndexMatch = tab.id.match(/\d+$/i)
      if (!tabIndexMatch) return
      const tabIndex = tabIndexMatch[0]
      const state = localStorage.getItem(`${tabsPanel}${tabIndex}`)

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
