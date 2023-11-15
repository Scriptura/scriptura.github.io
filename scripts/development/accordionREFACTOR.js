'use strict'

/**
 * @documentation :
 * Le html d'origine est composée de details > summary + div :
 *.accordion
 *  details
 *    summary Title item
 *    div Content item
 * La première partie du script transforme ce code impossible à animer, en récupérant les attributs de leur état d'origine (ouvert/fermé) :
 *.accordion
 *  div.accordion-details
 *  button.accordion-summary Title item
 *  div.accordion-panel Content item
 * La deuxième partie du code concerne les changements d'états des onglets/panneaux (ouvert/fermé).
 *
 * @param, deux options :
 * @option 'open' : onglet ouvert par défaut ; à définir sur l'élément <details> via l'attribut 'open' (comportement html natif)
 * @option 'singleTab' : un seul onglet s'ouvre à la fois ; à définir sur la div.accordion via l'attribut data-singletab
 *
 * 1. Option 'open'
 * 2. Option 'singleTab'
 *
 * Inspiration pour les rôles et les attributs aria :
 * @see https://www.w3.org/TR/wai-aria-practices-1.1/examples/accordion/accordion.html
 * @see https://jqueryui.com/accordion/
 * @see http://accessibility.athena-ict.com/aria/examples/tabpanel2.shtml
 */

const accordion = () => {

  const init = () => {
    transformItems(document.querySelectorAll('.accordion > details'))
    addEventListenerOnButtons(document.querySelectorAll('.accordion-summary'))
  }

  const transformItems = items => {
    items.forEach((item, i) => {
      i++
      replaceSummaryElement(item.firstElementChild, i)
      replacePanelElement(item.lastElementChild, i)
      replaceDetailsElement(item)
    })
  }

  const replaceDetailsElement = details => {
    const item = document.createElement('div')
    item.classList.add('accordion-details') 
    item.innerHTML = details.innerHTML
    details.replaceWith(item)
    if (details.open) openItem(item)
  }

  const replaceSummaryElement = (summary, i) => summary.outerHTML = `<button id="accordion-summary-${i}" type="button" class="accordion-summary" role="tab" aria-controls="accordion-panel-${i}" aria-expanded="false">${summary.innerHTML}</button>`

  const replacePanelElement = (panel, i) => panel.outerHTML = `<div id="accordion-panel-${i}" class="accordion-panel" role="tabpanel" aria-hidden="true">${panel.innerHTML}</div>`

  const openItem = item => {
    item.classList.add('open') // 1
    if (item.classList.contains('open')) item.firstElementChild.ariaExpanded = 'true'
    togglePanel(getPanel(item))
  }

  const addEventListenerOnButtons = buttons => buttons.forEach(button => button.addEventListener('click', () => onTogglePanel(button)))

  const closeAllOtherItems = item => getOtherItems(item).forEach(_ => closeItem(_))

  const closeItem = item => {
    item.classList.remove('open')
    item.firstElementChild.ariaExpanded = 'false'
    closePanel(getPanel(item))
  }

  const onTogglePanel = button => {
    const singleTabOption = button.parentElement.parentElement.dataset.singletab // 2
    const item = button.parentElement
    toggleItem(item, singleTabOption)
  }

  const toggleItem = (item, singleTabOption) => {
    let button = item.firstElementChild
    item.classList.toggle('open')
    item.classList.contains('open') ? button.ariaExpanded = 'true' : button.ariaExpanded = 'false' // @todo En test.
    if (singleTabOption) closeAllOtherItems(item)
    togglePanel(getPanel(item))
  }

  const togglePanel = panel => panel.style.maxHeight ? closePanel(panel) : openPanel(panel)

  const closePanel = panel => {
    panel.dataset.height = '0' // @todo TEST
    panel.removeAttribute('style') //panel.style.maxHeight = null
    panel.setAttribute('aria-hidden', 'true')
  }

  const openPanel = panel => {
    panel.dataset.height = panel.scrollHeight // @todo TEST
    panel.style.maxHeight = panel.dataset.height + 'px'
    panel.setAttribute('aria-hidden', 'false')
    //panel.addEventListener('transitionend', () => panel.removeAttribute('style'))
  }

  const getPanel = item => item.lastElementChild

  const getOtherItems = item => [...item.parentElement.children].filter(_ => _ !== item)

  init()

}

window.addEventListener('DOMContentLoaded', accordion()) // @note S'assurer que le script est bien chargé après le DOM et ce quelque soit la manière dont il est appelé.
