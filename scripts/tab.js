'use strict'

const tabs = (() => {
  const addTablist = (() => {
    for (const tabs of document.querySelectorAll('.tabs')) {
      const tabList = document.createElement('div')
      tabList.classList.add('tab-list')
      tabList.setAttribute('role', 'tablist')
      tabList.setAttribute('aria-label', 'Entertainment')
      tabs.prepend(tabList)
    }
  })()
  const transformationOfSummariesIntoTabs = (() => {
    let i = 0
    for (const summary of document.querySelectorAll('.tabs > * > summary')) {
      i++
      const tablist = summary.parentElement.parentElement.firstElementChild,
            summaryHtml = summary.innerHTML,
            tab = document.createElement('button')
      tab.id = 'tab-summary-' + i
      tab.type = 'button'
      tab.classList.add('tab-summary')
      tab.setAttribute('role', 'tab')
      tab.setAttribute('aria-controls', 'tab-panel-' + i)
      tablist.appendChild(tab)
      tab.insertAdjacentHTML('beforeend', summaryHtml)
      summary.parentElement.removeChild(summary)
    }
  })()
  const transformationOfElementsIntoPannels = (() => {
    let i = 0
    for (const panel of document.querySelectorAll('.tabs > details > *')) {
      i++
      panel.id = 'tab-panel-' + i
      panel.classList.add('tab-panel')
      panel.setAttribute('role', 'tabpanel')
      panel.setAttribute('aria-labelledby', 'tabsummary-' + i)
      panel.parentElement.parentElement.appendChild(panel)
      panel.parentElement.querySelector('details').remove()
    }
  })()
  const currentTab = (() => {
    for (const firstTab of document.querySelectorAll('.tab-summary:first-child')) {
      firstTab.disabled = true
      firstTab.classList.add('current')
      firstTab.setAttribute('aria-selected', 'true')
    }
    for (const tab of document.querySelectorAll('.tab-summary')) {
      tab.addEventListener('click', () => {
        for (const tabSibling of tab.parentElement.children) {
          tabSibling.disabled = false
          tabSibling.classList.remove('current')
          tabSibling.setAttribute('aria-selected', 'false')
        }
        tab.disabled = true
        tab.classList.add('current')
        tab.setAttribute('aria-selected', 'true')
      })
    }
  })()
  const currentPanel = (() => {
    for (const tab of document.querySelectorAll('.tab-summary')) {
      tab.addEventListener('click', () => {
        const currentPanel = document.getElementById(tab.getAttribute('aria-controls'))
        currentPanel.style.display = 'block'
        for (const panel of tab.parentElement.parentElement.querySelectorAll('.tab-panel')) {
          if (panel === currentPanel) continue
          if(panel.parentElement === tab.parentElement.parentElement) panel.style.display = 'none'
          if (tab === tab.classList.contains('current')) tab.classList.remove('current')
        }
      })
    }
  })()
})()
