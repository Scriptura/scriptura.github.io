'use strict'

/**
 * @summary Attache une saisie multi-termes à un `<input>` avec support datalist.
 * Les termes sont séparés par Entrée, `,` ou `;`, affichés sous forme de tags
 * supprimables, et persistés dans un input caché `.input-terms`.
 *
 * @strategy
 * - `activeTerms: Set<string>` comme source de vérité unique pour les termes
 *   actifs. Élimine toutes les lectures DOM de déduplication (`textContent`,
 *   `getElementsByClassName`).
 * - `data-value` sur chaque tag : le nœud DOM porte sa valeur sans dépendre
 *   de `textContent` ni de `slice()`.
 * - `syncMainInput` lit `activeTerms` directement : zéro requête DOM.
 * - `datalist.querySelector` avec `CSS.escape` pour les lookups d'options :
 *   plus robuste que l'itération `getElementsByTagName`.
 * - Guard `focusout` via `relatedTarget` : évite l'ajout parasite d'un terme
 *   lors d'un clic sur un bouton de suppression dans le même composant.
 * - Navigation clavier limitée aux `.term-btn` : seul élément focusable utile
 *   dans le container.
 *
 * @architectural-decision
 * - `initialOptions: Set<string>` : snapshot AOT des options datalist d'origine.
 *   Sert uniquement à décider si une option doit être restaurée à la suppression
 *   d'un terme. Non muté après init.
 * - Un terme absent du datalist est marqué `new-term`. Ce signal CSS est un
 *   contrat UX avec le backend : signifie "valeur libre, à créer". À documenter
 *   côté serveur si la distinction est exploitée au submit.
 * - `mainInput.value` est en virgule+espace (`, `). Si le séparateur doit
 *   changer (ex: pipe pour le backend), modifier uniquement `syncMainInput`
 *   et le `split` d'initialisation.
 * - `multipleTerms` est une fonction appelée par composant. Pas de state global :
 *   chaque instance est autonome. Plusieurs composants sur la même page sont
 *   supportés sans conflit.
 * - Pas de `DOMContentLoaded` : suppose exécution différée (`defer`) ou
 *   position en fin de `<body>`.
 */

function multipleTerms(input) {
  const listId        = input.getAttribute('list')
  const datalist      = listId ? document.getElementById(listId) : null
  const termContainer = input.parentElement?.querySelector('.term-container')
  const mainInput     = input.parentElement?.querySelector('.input-terms')

  if (!datalist || !termContainer || !mainInput) return

  // — État ——————————————————————————————————————————————————————————————————

  const initialOptions = new Set(Array.from(datalist.options, o => o.value))
  const activeTerms    = new Set()

  // — Init depuis mainInput ——————————————————————————————————————————————————

  for (const raw of mainInput.value.split(',')) {
    const term = raw.trim()
    if (term) addTerm(term)
  }

  // — Listeners input ———————————————————————————————————————————————————————

  input.addEventListener('keydown', event => {
    if (event.key !== 'Enter' && event.key !== ',' && event.key !== ';') return
    event.preventDefault()
    const value = input.value.trim()
    if (!value) return
    addTerm(value)
    input.value = ''
    syncMainInput()
  })

  input.addEventListener('focusout', event => {
    if (
      event.relatedTarget instanceof Node &&
      (termContainer.contains(event.relatedTarget) || event.relatedTarget === input)
    ) return

    const value = input.value.trim().replace(/[;,]$/, '')
    if (!value) return
    addTerm(value)
    input.value = ''
    syncMainInput()
  })

  // — Navigation clavier ————————————————————————————————————————————————————

  termContainer.addEventListener('keydown', event => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return
    const btns  = Array.from(termContainer.querySelectorAll('.term-btn'))
    const index = btns.indexOf(document.activeElement)
    if (index === -1) return
    if (event.key === 'ArrowLeft'  && index > 0)              btns[index - 1].focus()
    if (event.key === 'ArrowRight' && index < btns.length - 1) btns[index + 1].focus()
  })

  // — Core ——————————————————————————————————————————————————————————————————

  function addTerm(text) {
    if (activeTerms.has(text)) return
    activeTerms.add(text)

    const inDatalist = initialOptions.has(text)
    if (inDatalist) removeOption(text)

    const termEl = document.createElement('div')
    termEl.classList.add('term')
    termEl.dataset.value = text
    if (!inDatalist) termEl.classList.add('new-term')

    const span = document.createElement('span')
    span.textContent = text

    const btn = document.createElement('button')
    btn.type = 'button'
    btn.textContent = '×'
    btn.classList.add('term-btn')
    btn.setAttribute('aria-label', `Supprimer ${text}`)
    btn.addEventListener('click', () => {
      activeTerms.delete(text)
      if (inDatalist) addOption(text)
      termEl.remove()
      syncMainInput()
    })

    termEl.append(span, btn)
    termContainer.appendChild(termEl)
  }

  function removeOption(text) {
    const option = datalist.querySelector(`option[value="${CSS.escape(text)}"]`)
    option?.remove()
  }

  function addOption(text) {
    const option = document.createElement('option')
    option.value = text
    datalist.appendChild(option)
  }

  function syncMainInput() {
    mainInput.value = Array.from(activeTerms).join(', ')
  }
}

// — Init ————————————————————————————————————————————————————————————————————

document.querySelectorAll('.input-add-terms').forEach(input => multipleTerms(input))
