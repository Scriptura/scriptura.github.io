/**
 * Enregistre un Service Worker pour l'application si le navigateur le supporte.
 * @see https://developer.mozilla.org/fr/docs/Web/API/Service_Worker_API/Using_Service_Workers
 * @async
 * @function
 * @returns {Promise<void>} Une promesse qui se résout lorsque l'enregistrement du Service Worker est terminé.
 */
async function registerServiceWorker() {
  if ('serviceWorker' in navigator) {
    try {
      const registration = await navigator.serviceWorker.register('/app/UA0/sw.js')

      if (registration.installing) {
        console.log('Installation du service worker en cours')
      } else if (registration.waiting) {
        console.log('Service worker installé')
      } else if (registration.active) {
        console.log('Service worker actif')
      }
    } catch (error) {
      console.error(`L'enregistrement du service worker a échoué : ${error}`)
    }
  }
}

registerServiceWorker()

// Lancement de l'impression :
;(function addPrintEventListener() {
  const printButtons = document.querySelectorAll('.cmd-print')

  for (const printButton of printButtons) {
    printButton.onclick = function () {
      window.print()
    }
  }
})()

// Ajuste la hauteur du champ par rapport au contenu
function textareaAutosize(textarea) {
  const targetForTextareas = document.querySelectorAll('.target-for-textarea')

  const adjustHeight = () => {
    textarea.style.height = 'auto'
    textarea.style.height = `${textarea.scrollHeight}px`
  }
  window.addEventListener('load', adjustHeight)
  window.addEventListener('resize', adjustHeight)
  textarea.addEventListener('input', adjustHeight)
  textarea.addEventListener('focus', adjustHeight)
  targetForTextareas.forEach(target => {
    target.addEventListener('change', adjustHeight)
    target.addEventListener('click', () => {
      adjustHeight()
      setTimeout(adjustHeight, 1) // un petit hack pour les mobiles...
    })
  })
}
document.querySelectorAll('textarea.autosize').forEach(textarea => textareaAutosize(textarea))

// Fonction pour définir l'état 'disabled' des éléments en fonction de la persistance
function updateDisabledState() {
  const isScheduleDataSet = localStorage.getItem('scheduleData') !== null
  document.querySelector('select#pattern-select').disabled = isScheduleDataSet
  document.querySelector('input#start-date').disabled = isScheduleDataSet
  document.querySelector('#generate-schedule').disabled = isScheduleDataSet

  if (isScheduleDataSet) {
    // Mise à jour des boutons de visibilité
    document.querySelectorAll('.visibility').forEach(el => {
      el.classList.add('visible')
      el.classList.remove('hidden')
    })
  }
}

// Initialisation de l'état des éléments au chargement de la page
document.addEventListener('DOMContentLoaded', () => {
  updateDisabledState()
})

// Écouteur de clic pour le bouton #generate-schedule
document.querySelector('#generate-schedule').addEventListener('click', e => {
  const startDateInput = document.querySelector('input#start-date')

  // Vérifie si 'input#start-date' est renseigné, sinon, annule le script
  if (!startDateInput.value) {
    console.warn("L'input #start-date doit être renseigné avant de générer le calendrier.")
    return
  }

  document.querySelector('#generate-schedule').disabled = true
  document.querySelector('select#pattern-select').disabled = true
  startDateInput.disabled = true

  // Mise à jour des boutons de visibilité
  document.querySelectorAll('.visibility').forEach(el => {
    el.classList.toggle('visible')
    el.classList.toggle('hidden')
    //el.classList.remove((('hidden')))
  })
})

document.querySelector('#reset').addEventListener('click', () => {
  // Réactivation des éléments si scheduleData n'est pas présent
  if (!localStorage.getItem('scheduleData')) {
    document.querySelector('select#pattern-select').disabled = false
    document.querySelector('input#start-date').disabled = false
  }
})

/**
 * Met à jour le texte avec l'année en cours.
 * @param {string} elementId - ID de l'élément à mettre à jour.
 */
function updateYearInTitle(elementId) {
  const currentYear = new Date().getFullYear()
  const element = document.getElementById(elementId)

  if (element) {
    element.textContent = currentYear
  } else {
    console.warn(`L'élément avec l'ID "${elementId}" est introuvable.`)
  }
}

updateYearInTitle('current-year-stats')

// Items modifiables dans la liste des statistiques `.stats-list`
document.addEventListener('DOMContentLoaded', () => {
  const list = document.querySelector('.stats-list')

  loadFromLocalStorage()

  list.addEventListener('input', event => {
    // Détecter les modifications en temps réel
    if (event.target.getAttribute('contenteditable') === 'true') {
      saveToLocalStorage()
    }
  })

  function saveToLocalStorage() {
    const items = Array.from(list.querySelectorAll('li'))
      .map(li => {
        const codeElement = li.querySelector('.event-other')
        const textElement = li.querySelector('[contenteditable="true"]')

        return {
          code: codeElement ? codeElement.textContent : '',
          text: textElement ? textElement.textContent : '',
        }
      })
      .filter(item => item.text.trim() !== '')

    localStorage.setItem('editableItems', JSON.stringify(items))
  }

  function loadFromLocalStorage() {
    const savedItems = localStorage.getItem('editableItems')

    if (savedItems) {
      try {
        const items = JSON.parse(savedItems)

        const contentEditableElements = list.querySelectorAll('[contenteditable="true"]')

        // Mettre à jour les éléments existants
        items.forEach((item, i) => {
          if (i < contentEditableElements.length) {
            contentEditableElements[i].textContent = item.text
          }
        })
      } catch (error) {
        console.error('Erreur lors du chargement des données:', error)
      }
    }
  }
})
