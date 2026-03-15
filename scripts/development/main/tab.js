/**
 * @module TabsSystem
 * @version 2.1.0
 * @author Architecte Système
 * * @description
 * SYSTÈME DE GESTION D'ONGLETS À PERSISTENCE CONTEXTUELLE.
 * * --- ARBITRAGES DE CONCEPTION (DOD / AOT) ---
 * * 1. PIPELINE À DEUX PHASES :
 * - Phase 1 (JIT Transform) : Si le conteneur .tabs contient des enfants 'details',
 * le script transmute dynamiquement le DOM vers une structure ARIA (Buttons/Panels).
 * Cela permet de garder un HTML source (Pug) minimal et sémantique.
 * - Phase 2 (State Engine) : Gestionnaire d'état agnostique. Il s'attache à la
 * structure (qu'elle soit native ou générée) via des contrats d'attributs (role, aria-controls).
 * * 2. ISOLATION PAR :SCOPE (ANTI-COLLISION) :
 * - Utilisation systématique du sélecteur ':scope >' pour garantir que les opérations
 * de recherche (querySelectorAll) ne polluent pas les systèmes d'onglets imbriqués
 * (Nested Tabs). Chaque instance est une cellule isolée.
 * * 3. PERSISTENCE PAR NAMESPACE (SLUG-BASED) :
 * - Stockage dans localStorage['tabsState'].
 * - Segmentation par 'slug' (window.location.pathname) : garantit que l'état d'un onglet
 * sur la page A n'écrase pas celui de la page B.
 * - Clés déterministes (t-cIdx-tIdx) : assure un mapping stable entre le DOM et le
 * stockage, même sans IDs explicites en base.
 * * 4. RENDU DÉLÉGUÉ (CSS-CENTRIC) :
 * - Le script ne modifie pas les styles 'inline'. Il mute l'état logique [aria-hidden].
 * - Le moteur de rendu du navigateur assure l'éviction du layout via le CSS :
 * .tab-panel[aria-hidden="true"] { display: none; }
 *
 * TODO: FUTURE EVOLUTION (Safari Support > 100%)
 * Remplacer le pattern [aria-hidden="true"] + CSS [display: none] 
 * par l'attribut HTML5 [hidden="until-found"].
 * * AVANTAGES :
 * 1. Indexation native du contenu par le navigateur (Find-in-page).
 * 2. Suppression de la dépendance CSS pour l'éviction du layout.
 * * MÉCANIQUE À IMPLÉMENTER :
 * - Remplacer .setAttribute('aria-hidden', 'true') par .setAttribute('hidden', 'until-found').
 * - Écouter l'événement 'beforematch' sur les .tab-panel pour déclencher 
 * automatiquement le syncGroupState(tabCorrespondante) lorsque l'utilisateur 
 * effectue une recherche.
 */

'use strict'

const tabsSystem = () => {
  const slug = window.location.pathname
  const STATE_KEY = 'tabsState'

  const getStoredState = () => {
    const stored = localStorage.getItem(STATE_KEY)
    const parsed = stored ? JSON.parse(stored) : { tabsState: {} }
    if (!parsed.tabsState[slug]) parsed.tabsState[slug] = {}
    return parsed
  }

  const saveStoredState = (state) => {
    localStorage.setItem(STATE_KEY, JSON.stringify(state))
  }

  /**
   * Transformation du layout "Raw" (details/summary) vers "Cooked" (tabs/panels)
   * Focalisation sur l'isolation via :scope
   */
  const transformContainer = (container, containerIdx) => {
    const rawEntities = container.querySelectorAll(':scope > details')
    if (rawEntities.length === 0) return

    const tabList = document.createElement('div')
    tabList.setAttribute('role', 'tablist')
    tabList.className = 'tab-list'

    rawEntities.forEach((details, tabIdx) => {
      const summary = details.querySelector(':scope > summary')
      const content = details.querySelector(':scope > :not(summary)')
      const entityId = `t-${containerIdx}-${tabIdx}`

      // Create Trigger
      const btn = document.createElement('button')
      btn.id = `btn-${entityId}`
      btn.type = 'button'
      btn.role = 'tab'
      btn.className = 'tab-summary'
      btn.setAttribute('aria-controls', `pnl-${entityId}`)
      btn.innerHTML = summary.innerHTML
      tabList.appendChild(btn)

      // Create Panel
      content.id = `pnl-${entityId}`
      content.classList.add('tab-panel')
      content.setAttribute('role', 'tabpanel')
      content.setAttribute('aria-labelledby', btn.id)
      
      container.appendChild(content)
      details.remove()
    })

    container.prepend(tabList)
  }

  /**
   * Synchronisation de l'état (State -> UI)
   */
  const syncGroupState = (activeTab, container) => {
    const targetId = activeTab.getAttribute('aria-controls')
    const tabs = container.querySelectorAll(':scope > .tab-list > [role="tab"]')
    const panels = container.querySelectorAll(':scope > .tab-panel')
    const fullState = getStoredState()

    tabs.forEach(tab => {
      const isActive = (tab === activeTab)
      tab.disabled = isActive
      tab.setAttribute('aria-selected', isActive)
      tab.setAttribute('aria-expanded', isActive)
      fullState.tabsState[slug][tab.id] = isActive ? 'open' : 'close'
    })

    panels.forEach(p => p.setAttribute('aria-hidden', p.id !== targetId))
    saveStoredState(fullState)
  }

  const init = () => {
    const containers = document.querySelectorAll('.tabs')
    const pageState = getStoredState().tabsState[slug]

    containers.forEach((container, cIdx) => {
      // 1. Transformation si nécessaire (Data Layout)
      transformContainer(container, cIdx)

      // 2. Acquisition des entités (Logic)
      const tabs = container.querySelectorAll(':scope > .tab-list > [role="tab"]')
      if (tabs.length === 0) return

      const activeTab = [...tabs].find(t => pageState[t.id] === 'open') || tabs[0]

      tabs.forEach(tab => {
        tab.addEventListener('click', () => syncGroupState(tab, container))
      })

      // 3. Premier cycle (Render)
      syncGroupState(activeTab, container)
    })
  }

  init()
}

// Initialisation au chargement
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', tabsSystem)
} else {
  tabsSystem()
}
