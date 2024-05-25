'use strict'

/**
 * Attache la fonctionnalité d'entrée de plusieurs termes à un élément input avec prise en charge de datalist.
 *
 * Cette fonction améliore un élément input donné pour permettre à l'utilisateur d'entrer plusieurs termes, séparés par 'Entrée', ',', ou ';'.
 * Chaque terme est affiché dans un conteneur de termes avec la possibilité de le supprimer.
 * Les termes sont également validés par rapport à un élément datalist associé pour les options prédéfinies.
 * Les termes ajoutés sont également stockés dans un input principal sous forme de texte séparé par des virgules.
 * Les valeurs initialement présentes dans l'input principal sont également prises en compte et ajoutées au conteneur de termes.
 *
 * @param {HTMLInputElement} input - L'élément input auquel la fonctionnalité de plusieurs termes est attachée. L'élément input doit avoir un attribut 'list' pointant vers un élément datalist.
 *
 * La fonction effectue les actions suivantes :
 * - Lorsque l'utilisateur tape un terme suivi de 'Entrée', ',', ou ';', le terme est ajouté à un conteneur de termes.
 * - L'entrée est effacée après l'ajout d'un terme.
 * - Si l'entrée perd le focus avec une valeur non vide, la valeur est ajoutée en tant que terme.
 * - Chaque terme est affiché dans le conteneur de termes avec un bouton de suppression associé.
 * - Le terme est vérifié par rapport aux options dans le datalist. S'il n'est pas présent, il est marqué comme un nouveau terme.
 * - Le terme peut être supprimé en cliquant sur le bouton de suppression associé.
 * - La navigation à travers les termes en utilisant les touches 'Flèche gauche' et 'Flèche droite' est prise en charge.
 * - Les termes ajoutés sont également stockés dans un input principal ('.input-terms') sous forme de texte séparé par des virgules.
 * - Les valeurs initialement présentes dans l'input principal sont également prises en compte et ajoutées au conteneur de termes.
 **/
function multipleTerms(input) {
  const datalist = document.getElementById(input.getAttribute('list'))
  const termContainer = input.parentElement.querySelector('.term-container')
  const initialOptions = new Set(Array.from(datalist.options).map(option => option.value))
  const mainInput = input.parentElement.querySelector('.input-terms')

  // Initialiser les termes déjà présents dans l'input principal
  const initialTerms = mainInput.value.split(',').map(term => term.trim()).filter(term => term !== '')
  initialTerms.forEach(term => addTerm(term))

  input.addEventListener('keydown', function (event) {
    if (['Enter', ',', ';'].includes(event.key)) {
      event.preventDefault()
      const value = input.value.trim()
      if (value) {
        addTerm(value)
        input.value = ''
        updateMainInput()
      }
    }
  })

  input.addEventListener('focusout', function () {
    const value = input.value.trim().replace(/[;,]$/, '')
    if (value) {
      addTerm(value)
      input.value = ''
      updateMainInput()
    }
  })

  function addTerm(text) {
    if (!isTermPresent(text)) {
      const term = document.createElement('div')

      const termText = document.createElement('span')
      termText.textContent = text
      term.appendChild(termText)

      const removeBtn = document.createElement('button')
      removeBtn.textContent = '×'
      removeBtn.setAttribute('aria-label', `Supprimer ${text}`)
      removeBtn.addEventListener('click', () => {
        removeTerm(text)
        termContainer.removeChild(term)
        updateMainInput()
      })

      removeBtn.addEventListener('keydown', function (event) {
        if (['Enter', ' '].includes(event.key)) {
          removeBtn.click()
        }
      })

      term.appendChild(removeBtn)

      if (!isOptionPresent(text)) {
        term.classList.add('new-term')
      }

      term.classList.add('term')
      termContainer.appendChild(term)
      removeOption(text)
    }
  }

  function removeTerm(text) {
    if (initialOptions.has(text)) {
      addOption(text)
    }
  }

  function isTermPresent(text) {
    return Array.from(termContainer.getElementsByClassName('term')).some(term => term.textContent.slice(0, -1) === text)
  }

  function removeOption(text) {
    const option = Array.from(datalist.getElementsByTagName('option')).find(option => option.value === text)
    if (option) {
      datalist.removeChild(option)
    }
  }

  function addOption(text) {
    const option = document.createElement('option')
    option.value = text
    datalist.appendChild(option)
  }

  function isOptionPresent(text) {
    return Array.from(datalist.getElementsByTagName('option')).some(option => option.value === text)
  }

  function updateMainInput() {
    const terms = Array.from(termContainer.getElementsByClassName('term')).map(term => term.textContent.slice(0, -1))
    mainInput.value = terms.join(', ')
  }

  termContainer.addEventListener('keydown', event => {
    const focusableTerms = Array.from(termContainer.querySelectorAll('.term, .term button'))
    const index = focusableTerms.indexOf(document.activeElement)

    if (event.key === 'ArrowLeft' && index > 0) {
      focusableTerms[index - 1].focus()
    } else if (event.key === 'ArrowRight' && index < focusableTerms.length - 1) {
      focusableTerms[index + 1].focus()
    }
  })
}

document.querySelectorAll('.input-add-terms').forEach(input => multipleTerms(input))
