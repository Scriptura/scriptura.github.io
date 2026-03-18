'use strict'

/**
 * @summary Affiche les informations techniques du client dans l'élément `.client-test`.
 *
 * @strategy
 *   – Séparation stricte données statiques / données dynamiques : OS, navigateur et
 *     résolution écran sont calculés une seule fois au boot (AOT) et mis en cache.
 *     Seules les dimensions de fenêtre sont relues à chaque resize.
 *   – Injection DOM en un seul passage : les cinq lignes sont concaténées en une
 *     string avant l'unique affectation à innerHTML, évitant les re-parse répétés.
 *   – Référence DOM capturée une fois à l'init, jamais re-requêtée sur les events.
 *
 * @architectural-decision
 *   – userAgent est deprecié mais reste la seule solution cross-browser sans dépendance
 *     externe pour ce niveau de détection (usage interne, non critique).
 *   – Le timer de debounce resize est déclaré dans la portée du module et non dans le
 *     handler, condition nécessaire pour que clearTimeout soit opérant.
 *   – Pas de listener 'load' / guard readyState : ce script est injecté via script.async
 *     post-DOMContentLoaded (pipeline more.js). Le DOM est garanti disponible à
 *     l'évaluation — appel direct de boot().
 */
const ClientTestSystem = (() => {
  // ---------------------------------------------------------------------------
  // 1. Data Layout
  // ---------------------------------------------------------------------------

  // Données statiques : calculées une fois, jamais recalculées
  const agent = navigator.userAgent
  const agentLow = agent.toLowerCase()

  const os = (() => {
    if (agent.includes('Win'))      return 'Windows'
    if (agent.includes('Android'))  return 'Android'
    if (agent.includes('like Mac')) return 'iOS'
    if (agent.includes('Mac'))      return 'Macintosh'
    if (agent.includes('Linux'))    return 'Linux'
    return 'Unknown OS'
  })()

  const browser = (() => {
    if (agentLow.includes('edge'))                           return 'MS Edge'
    if (agentLow.includes('edg/'))                          return 'Edge (Chromium)'
    if (agentLow.includes('opr')  && window.opr)            return 'Opera'
    if (agentLow.includes('chrome') && window.chrome)       return 'Chrome'
    if (agentLow.includes('trident'))                       return 'MS IE'
    if (agentLow.includes('firefox'))                       return 'Firefox'
    if (agentLow.includes('safari'))                        return 'Safari'
    return 'Unknown'
  })()

  const screenInfo = `${screen.width}×${screen.height}px — ${screen.pixelDepth} bits`

  // ---------------------------------------------------------------------------
  // 2. System
  // ---------------------------------------------------------------------------

  let el = null
  let _resizeTimer = null

  const render = () => {
    if (!el) return
    el.innerHTML =
      `<li>Système d'exploitation&nbsp;: ${os}</li>` +
      `<li>Navigateur&nbsp;: ${browser}</li>` +
      `<li>Résolution écran&nbsp;: ${screenInfo}</li>` +
      `<li>Fenêtre de navigation&nbsp;: ${window.innerWidth}×${window.innerHeight}px</li>`
  }

  // ---------------------------------------------------------------------------
  // 3. Boot
  // ---------------------------------------------------------------------------

  const boot = () => {
    el = document.querySelector('.client-test')
    if (!el) return

    render()

    window.addEventListener('resize', () => {
      clearTimeout(_resizeTimer)
      _resizeTimer = setTimeout(render, 200)
    })
  }

  return { boot }
})()

// Ce script est injecté en async post-DOMContentLoaded : exécution immédiate garantie.
ClientTestSystem.boot()
