document.addEventListener('DOMContentLoaded', () => {
  const editableButton = document.querySelector('.contenteditable')
  const spanText = editableButton.querySelector('span')

  editableButton.addEventListener('click', () => {
    console.log('Bouton éditer cliqué') // Ajoutez ceci pour tester
    // Reste du code...
  })

  // On utilise une délégation d'événements au niveau du conteneur parent
  const calendarDiv = document.getElementById('calendar')

  // Variable pour suivre l'état d'édition
  let isEditingEnabled = false

  editableButton.addEventListener('click', () => {
    const tables = document.querySelectorAll('table[id^="month-"]')
    if (!tables.length) {
      alert("Veuillez d'abord générer le planning.")
      return
    }

    isEditingEnabled = !isEditingEnabled

    // Sélection des deux <span> dans le bouton
    const [editText, disableEditText] = editableButton.querySelectorAll('span')
  
    if (isEditingEnabled) {
      enableEditing()
      editText.classList.add('hidden')
      disableEditText.classList.remove('hidden')
      editableButton.classList.add('active')
    } else {
      disableEditing()
      editText.classList.remove('hidden')
      disableEditText.classList.add('hidden')
      editableButton.classList.remove('active')
    }
  })

  // Utiliser la délégation d'événements pour gérer les clics sur les cellules
  calendarDiv.addEventListener('click', e => {
    if (!isEditingEnabled) return

    const cell = e.target.closest('td[data-day]')
    if (cell) {
      cell.setAttribute('contenteditable', 'true')
      cell.focus()
    }
  })

  // Gérer l'input sur les cellules (délégation d'événements)
  calendarDiv.addEventListener('input', e => {
    if (!isEditingEnabled) return

    const cell = e.target.closest('td[data-day]')
    if (!cell) return

    const value = cell.textContent.trim().toUpperCase()
    if (value.length > 1) {
      cell.textContent = value.charAt(0)
    }
  })

  // Gérer la perte de focus (délégation d'événements)
  calendarDiv.addEventListener(
    'blur',
    e => {
      if (!isEditingEnabled) return

      const cell = e.target.closest('td[data-day]')
      if (!cell) return

      let value = cell.textContent.trim().toUpperCase()
      if (value) {
        // Valider que c'est une lettre valide
        const validLetters = ['J', 'S', 'M', 'R', 'T', 'F', 'N', 'C']
        if (!validLetters.includes(value)) {
          cell.textContent = ''
          return
        }

        // Mettre à jour la classe CSS en utilisant la fonction de planning.js
        if (typeof getClassFromSchedule === 'function') {
          const className = getClassFromSchedule(value)
          if (className) {
            // Supprimer les anciennes classes
            cell.className = ''
            cell.classList.add(className)
          }
        }
      }

      saveSchedule()
    },
    true,
  )

  function enableEditing() {
    const cells = calendarDiv.querySelectorAll('td[data-day]')
    cells.forEach(cell => {
      cell.style.cursor = 'pointer'
    })
  }

  function disableEditing() {
    const cells = calendarDiv.querySelectorAll('td[data-day]')
    cells.forEach(cell => {
      cell.removeAttribute('contenteditable')
      cell.style.cursor = ''
    })
    saveSchedule()
  }

  function saveSchedule() {
    const scheduleData = {}
    const tables = calendarDiv.querySelectorAll('table[id^="month-"]')

    tables.forEach(table => {
      const monthId = table.id
      const cells = table.querySelectorAll('td[data-day]')

      cells.forEach(cell => {
        const day = cell.getAttribute('data-day')
        const value = cell.textContent.trim()
        if (value) {
          if (!scheduleData[monthId]) {
            scheduleData[monthId] = {}
          }
          scheduleData[monthId][day] = value
        }
      })
    })

    localStorage.setItem('scheduleData', JSON.stringify(scheduleData))
  }

  function loadSchedule() {
    try {
      const savedData = JSON.parse(localStorage.getItem('scheduleData'))
      if (!savedData) return

      Object.entries(savedData).forEach(([monthId, monthData]) => {
        const table = document.getElementById(monthId)
        if (!table) return

        Object.entries(monthData).forEach(([day, value]) => {
          const cell = table.querySelector(`td[data-day="${day}"]`)
          if (cell) {
            cell.textContent = value
            if (typeof getClassFromSchedule === 'function') {
              const className = getClassFromSchedule(value)
              if (className) {
                cell.className = ''
                cell.classList.add(className)
              }
            }
          }
        })
      })
    } catch (error) {
      console.error('Erreur lors du chargement des données:', error)
    }
  }

  // Recharger les données après génération du planning
  const generateButton = document.querySelector('.generate-schedule')
  if (generateButton) {
    generateButton.addEventListener('click', () => {
      // Attendre que le planning soit généré
      setTimeout(loadSchedule, 100)
    })
  }
})
