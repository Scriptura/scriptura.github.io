'use strict'

const el = document.querySelector('.client-test')

const os = (function (agent) {
  switch (true) {
    case agent.indexOf('Win') != -1: return 'Windows'
    case agent.indexOf('Mac') != -1: return 'Macintosh'
    case agent.indexOf('Linux') != -1: return 'Linux'
    case agent.indexOf('Android') != -1: return 'Android'
    case agent.indexOf('like Mac') != -1: return 'iOS'
    default: return 'Unknown OS'
  }
})(navigator.userAgent)

const browserName = (function (agent) {
  switch (true) {
    case agent.indexOf('edge') > -1: return 'MS Edge'
    case agent.indexOf('edg/') > -1: return 'Edge ( chromium based)'
    case agent.indexOf('opr') > -1 && !!window.opr: return 'Opera'
    case agent.indexOf('chrome') > -1 && !!window.chrome: return 'Chrome'
    case agent.indexOf('trident') > -1: return 'MS IE'
    case agent.indexOf('firefox') > -1: return 'Mozilla Firefox'
    case agent.indexOf('safari') > -1: return 'Safari'
    default: return 'other'
  }
})(window.navigator.userAgent.toLowerCase())

el.innerHTML = `<li>Système d'exploitation&nbsp;: ${os}</i>`
el.innerHTML += `<li>Profondeur de l'écran&nbsp;: ${screen.pixelDepth} bits</i>`
el.innerHTML += `<li>Définition écran&nbsp;: ${screen.width} x ${screen.height}</i>`
el.innerHTML += `<li>Fenêtre de navigation&nbsp;: ${window.innerWidth} x ${window.innerHeight}</i>`
el.innerHTML += `<li>Navigateur&nbsp;: ${browserName}</i>`
