// Patterns de rotation

// prettier-ignore
const RotationPatterns = {
    IDE: [
      'J', 'J', 'S', 'J', 'J', 'R', 'R',
      'S', 'S', 'J', 'M', 'F', 'R', 'R',
      'S', 'J', 'M', 'M', 'R', 'S', 'S',
      'J', 'M', 'R', 'R', 'T', 'M', 'M',
      'M', 'R', 'J', 'S', 'S', 'R', 'R',
      'J', 'J', 'S', 'J', 'M', 'R', 'R',
      'S', 'S', 'J', 'J', 'M', 'R', 'R',
      'F', 'S', 'S', 'J', 'J', 'R', 'R',
      'M', 'M', 'M', 'R', 'S', 'S', 'S',
      'T', 'R', 'R', 'S', 'J', 'M', 'M',
      'R', 'J', 'J', 'S', 'S', 'R', 'R',
    ],
    NightIDE: [
      'N', 'N', 'R', 'R', 'N', 'N', 'N',
      'R', 'R', 'N', 'N', 'R', 'R', 'R',
    ],
    ASH: [
      'M', 'M', 'M', 'M', 'R', 'S', 'S',
      'S', 'S', 'R', 'R', 'M', 'M', 'M',
      'M', 'R', 'S', 'S', 'S', 'R', 'R',
      'T', 'M', 'M', 'M', 'M', 'R', 'R',
    ],
  }

// Gestionnaire de patterns personnalisés
const CustomPatternManager = {
  pattern: [],

  // Fonction pour formater le pattern pour l'affichage (groupes de 7 avec retours à la ligne)
  formatForDisplay(pattern) {
    const patternString = Array.isArray(pattern) ? pattern.join(',') : pattern
    const elements = patternString.split(',').map(el => el.trim())

    const weeks = []
    for (let i = 0; i < elements.length; i += 7) {
      const week = elements.slice(i, i + 7)
      weeks.push(week.join(', '))
    }
    return weeks.join(',\n')
  },

  // Fonction pour nettoyer et normaliser l'entrée utilisateur
  cleanInput(input) {
    return input
      .toUpperCase()
      .replace(/[\s\n\r\t]/g, '')
      .replace(/,+/g, ',')
      .replace(/^,/, '')
      .replace(/,$/, '')
  },

  // Fonction pour valider le pattern
  validate(pattern) {
    if (!pattern.trim()) {
      return true
    }

    const validChars = ['M', 'J', 'S', 'N', 'R', 'T', 'F']
    const patternArray = pattern.split(',')

    for (let char of patternArray) {
      char = char.trim()
      if (char && !validChars.includes(char)) {
        alert(`Caractère invalide détecté : "${char}"\nSeuls les caractères suivants sont autorisés : M, J, S, N, R, T, F`)
        return false
      }
    }
    return true
  },

  // Fonction pour convertir une chaîne en tableau
  stringToPattern(str) {
    return !str.trim() ? [] : this.cleanInput(str).split(',')
  },

  load() {
    const savedPattern = localStorage.getItem('rotation-custom-pattern')
    if (savedPattern) {
      this.pattern = JSON.parse(savedPattern)
    }
    return this.pattern.length > 0 ? this.pattern : RotationPatterns.IDE
  },

  save(pattern) {
    this.pattern = pattern
    localStorage.setItem('rotation-custom-pattern', JSON.stringify(pattern))
  },
}

// Gestionnaire de classes CSS pour les types de journée
const ScheduleClassManager = {
  getClass(scheduleLetter) {
    const classMap = {
      J: 'event-day',
      S: 'event-evening',
      M: 'event-morning',
      R: 'event-rest',
      T: 'event-extra-rest',
      F: 'event-holiday',
      N: 'event-night',
      C: 'event-leave',
      H: 'event-overtime',
      A: 'event-stop',
      G: 'event-strike',
      D: 'event-union',
      O: 'event-other',
    }
    return classMap[scheduleLetter] || null
  },
}

// Gestionnaire du calendrier
const CalendarManager = {
  generateSchedule(startDateInput, selectedPattern) {
    if (!startDateInput) {
      alert('Veuillez entrer une date de début.')
      return
    }

    const startDate = new Date(startDateInput)
    startDate.setDate(startDate.getDate() - 1)
    const calendarDiv = document.getElementById('calendar')
    calendarDiv.innerHTML = ''

    const daysOfWeek = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim']
    const displayStartDate = new Date()
    displayStartDate.setMonth(0) // Commence en janvier
    displayStartDate.setDate(1)

    // Obtenir le mois courant pour la comparaison
    const currentDate = new Date()
    const currentMonth = currentDate.getMonth()
    const currentYear = currentDate.getFullYear()

    for (let monthIndex = 0; monthIndex < 24; monthIndex++) {
      const monthDate = new Date(displayStartDate)
      monthDate.setMonth(displayStartDate.getMonth() + monthIndex)

      // Vérifier si c'est le mois courant
      const isCurrentMonth = monthDate.getMonth() === currentMonth && monthDate.getFullYear() === currentYear

      this.generateMonthTable(displayStartDate, monthIndex, startDate, selectedPattern, daysOfWeek, calendarDiv, isCurrentMonth)
    }

    // Sauvegarder le planning dès sa génération
    if (localStorage.getItem('scheduleData') === null) {
      StorageManager.saveSchedule(calendarDiv)
    }

    const buttons = document.querySelectorAll('button.visibility')
    buttons.forEach(button => {
      button.classList.toggle('visible')
      button.classList.toggle('hidden')
    })
  },

  generateMonthTable(displayStartDate, monthIndex, startDate, selectedPattern, daysOfWeek, calendarDiv, isCurrentMonth) {
    const monthDiv = document.createElement('div')
    const monthTable = document.createElement('table')
    monthTable.classList.add('table')

    // Ajouter la classe 'current' si c'est le mois courant
    if (isCurrentMonth) {
      monthTable.classList.add('current')
    }

    const currentMonth = new Date(displayStartDate)
    currentMonth.setMonth(displayStartDate.getMonth() + monthIndex)

    const monthYearId = `month-${currentMonth.getMonth() + 1}-${currentMonth.getFullYear()}`
    monthTable.id = monthYearId

    this.addTableHeader(monthTable, daysOfWeek)
    this.fillMonthTable(monthTable, currentMonth, startDate, selectedPattern)
    this.addTableCaption(monthTable, currentMonth)

    monthDiv.appendChild(monthTable)
    calendarDiv.appendChild(monthDiv)
  },

  addTableHeader(table, daysOfWeek) {
    const headerRow = document.createElement('tr')
    daysOfWeek.forEach(day => {
      const th = document.createElement('th')
      th.textContent = day
      headerRow.appendChild(th)
    })
    table.appendChild(headerRow)
  },

  fillMonthTable(table, currentMonth, startDate, selectedPattern) {
    const firstDay = new Date(currentMonth.getFullYear(), currentMonth.getMonth(), 1)
    const lastDay = new Date(currentMonth.getFullYear(), currentMonth.getMonth() + 1, 0)
    const firstWeekday = (firstDay.getDay() + 6) % 7
    const daysInMonth = lastDay.getDate()

    let row = document.createElement('tr')

    // Ajouter des cellules vides pour les jours précédant le premier du mois
    for (let i = 0; i < firstWeekday; i++) {
      row.appendChild(document.createElement('td'))
    }

    // Remplir les jours du mois
    for (let day = 1; day <= daysInMonth; day++) {
      const currentDate = new Date(currentMonth.getFullYear(), currentMonth.getMonth(), day)
      const daysSinceStart = Math.floor((currentDate - startDate) / (1000 * 60 * 60 * 24))

      // Calcul du bon index de rotation
      const rotationIndex = ((daysSinceStart % selectedPattern.length) + selectedPattern.length) % selectedPattern.length

      const dayCell = this.createDayCell(day, rotationIndex, selectedPattern)
      row.appendChild(dayCell)

      if ((firstWeekday + day) % 7 === 0) {
        table.appendChild(row)
        row = document.createElement('tr')
      }
    }

    // Remplir les cellules restantes de la dernière semaine
    while (row.children.length < 7) {
      row.appendChild(document.createElement('td'))
    }
    table.appendChild(row)
  },

  createDayCell(day, rotationIndex, selectedPattern) {
    const dayCell = document.createElement('td')
    dayCell.setAttribute('data-day', day)
    dayCell.setAttribute('tabindex', '0')

    if (rotationIndex !== null && selectedPattern[rotationIndex]) {
      const scheduleLetter = selectedPattern[rotationIndex]
      dayCell.textContent = scheduleLetter

      const className = ScheduleClassManager.getClass(scheduleLetter)
      if (className) {
        dayCell.classList.add(className)
      }
    }

    return dayCell
  },

  addTableCaption(table, currentMonth) {
    const caption = document.createElement('caption')
    caption.textContent = currentMonth
      .toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' })
      .replace(/^\p{CWU}/u, char => char.toLocaleUpperCase('fr-FR'))
    caption.classList.add('text-center')
    table.prepend(caption)
  },
}

// Gestionnaire de stockage local
const StorageManager = {
  saveSchedule(calendarDiv) {
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
  },

  loadSchedule(calendarDiv) {
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
            const className = ScheduleClassManager.getClass(value)
            if (className) {
              cell.className = ''
              cell.classList.add(className)
            }
          }
        })
      })
    } catch (error) {
      console.error('Erreur lors du chargement des données:', error)
    }
  },
}

// Gestionnaire d'édition du calendrier
const EditManager = {
  isEditingEnabled: false,

  toggleEditing(calendarDiv, editableButton) {
    const tables = document.querySelectorAll('table[id^="month-"]')
    if (!tables.length) {
      alert(`Veuillez d'abord générer le planning.`)
      return
    }

    this.isEditingEnabled = !this.isEditingEnabled
    const [editText, disableEditText] = editableButton.querySelectorAll('span')

    if (this.isEditingEnabled) {
      this.enableEditing(calendarDiv)
      editText.classList.add('hidden')
      disableEditText.classList.remove('hidden')
      editableButton.classList.add('active')
    } else {
      this.disableEditing(calendarDiv)
      editText.classList.remove('hidden')
      disableEditText.classList.add('hidden')
      editableButton.classList.remove('active')
    }
  },

  enableEditing(calendarDiv) {
    const cells = calendarDiv.querySelectorAll('td[data-day]')
    cells.forEach(cell => {
      cell.style.cursor = 'pointer'
    })
  },

  disableEditing(calendarDiv) {
    const cells = calendarDiv.querySelectorAll('td[data-day]')
    cells.forEach(cell => {
      cell.removeAttribute('contenteditable')
      cell.style.cursor = ''
    })
    StorageManager.saveSchedule(calendarDiv)
  },

  handleCellClick(e, calendarDiv) {
    if (!this.isEditingEnabled) return

    const cell = e.target.closest('td[data-day]')
    if (cell) {
      cell.setAttribute('contenteditable', 'true')
      cell.focus()

      // Créer un Range pour sélectionner tout le contenu de la cellule ; @note cell.select() ne fonctionne pas correctement dans ce cas de figure.
      const range = document.createRange()
      range.selectNodeContents(cell)

      // Obtenir la sélection actuelle et appliquer le range
      const selection = window.getSelection()
      selection.removeAllRanges()
      selection.addRange(range)

      // Sauvegarder la valeur initiale
      cell.dataset.initialValue = cell.textContent.trim().toUpperCase()
    }
  },

  handleCellInput(e, calendarDiv) {
    if (!this.isEditingEnabled) return

    const cell = e.target.closest('td[data-day]')
    if (!cell) return

    const value = cell.textContent.trim().toUpperCase()
    if (value.length > 1) {
      cell.textContent = value.charAt(0)
    } else {
      cell.textContent = value // Assure que la cellule affiche toujours en majuscules
    }
  },

  handleCellBlur(e, calendarDiv) {
    if (!this.isEditingEnabled) return

    const cell = e.target.closest('td[data-day]')
    if (!cell) return

    const newValue = cell.textContent.trim().toUpperCase()
    const initialValue = cell.dataset.initialValue

    if (newValue && newValue !== initialValue) {
      // Comparaison des valeurs formatées
      const validLetters = ['M', 'J', 'S', 'N', 'H', 'R', 'T', 'F', 'C', 'A', 'G', 'D', 'O']
      if (!validLetters.includes(newValue)) {
        cell.textContent = ''
        return
      }

      cell.textContent = newValue // Assure l'affichage en majuscules
      const className = ScheduleClassManager.getClass(newValue)
      if (className) {
        cell.className = ''
        cell.classList.add(className)
        cell.classList.add('modified')
        cell.removeAttribute('contenteditable')
      }
    }

    delete cell.dataset.initialValue // Nettoyage de la valeur initiale
    StorageManager.saveSchedule(calendarDiv)
  },
}

// Initialisation et gestionnaires d'événements
document.addEventListener('DOMContentLoaded', () => {
  const calendarDiv = document.getElementById('calendar')
  const editableButton = document.getElementById('contenteditable')
  const patternSelect = document.getElementById('pattern-select')
  const startDateInput = document.getElementById('start-date')
  const customPatternTextarea = document.getElementById('custom-pattern')
  const saveCustomPatternButton = document.getElementById('save-custom-pattern')
  const generateButton = document.getElementById('generate-schedule')

  // Fonction pour obtenir le pattern initial selon la sélection
  function getInitialPattern(patternType) {
    switch (patternType) {
      case 'NightIDE':
        return RotationPatterns.NightIDE
      case 'ASH':
        return RotationPatterns.ASH
      case 'CUSTOM':
        return CustomPatternManager.load()
      default:
        return RotationPatterns.IDE
    }
  }

  // Fonction pour mettre à jour le textarea avec le pattern sélectionné
  function updatePatternTextarea(pattern) {
    customPatternTextarea.value = CustomPatternManager.formatForDisplay(pattern)
  }

  // Fonction pour obtenir le pattern sélectionné
  function getSelectedPattern() {
    return CustomPatternManager.stringToPattern(customPatternTextarea.value)
  }

  // Gestionnaires d'événements pour le bouton d'édition
  editableButton.addEventListener('click', () => {
    EditManager.toggleEditing(calendarDiv, editableButton)
  })

  calendarDiv.addEventListener('click', e => {
    EditManager.handleCellClick(e, calendarDiv)
  })

  calendarDiv.addEventListener('input', e => {
    EditManager.handleCellInput(e, calendarDiv)
  })

  calendarDiv.addEventListener(
    'blur',
    e => {
      EditManager.handleCellBlur(e, calendarDiv)
    },
    true,
  )

  // Gestionnaire d'événement pour le changement de pattern
  patternSelect.addEventListener('change', function () {
    const initialPattern = getInitialPattern(this.value)
    updatePatternTextarea(initialPattern)
    localStorage.setItem('pattern-select', this.value)
  })

  // Gestionnaire d'événement pour la sauvegarde du pattern personnalisé
  saveCustomPatternButton.addEventListener('click', function () {
    const cleanedValue = CustomPatternManager.cleanInput(customPatternTextarea.value)

    if (CustomPatternManager.validate(cleanedValue)) {
      customPatternTextarea.value = CustomPatternManager.formatForDisplay(cleanedValue)
      const pattern = CustomPatternManager.stringToPattern(cleanedValue)
      CustomPatternManager.save(pattern)
    } else {
      const currentPattern = CustomPatternManager.pattern.length > 0 ? CustomPatternManager.pattern : getInitialPattern(patternSelect.value)
      updatePatternTextarea(currentPattern)
    }
  })

  // Gestionnaire d'événement pour la date de début
  startDateInput.addEventListener('change', function () {
    const selectedDate = new Date(this.value)
    const day = selectedDate.getDay()

    if (day !== 1) {
      alert('Veuillez sélectionner un lundi.')
      this.value = ''
    } else {
      localStorage.setItem('start-date', this.value)
    }
  })

  // Gestionnaire d'événement pour la génération du planning
  generateButton.addEventListener('click', () => {
    CalendarManager.generateSchedule(startDateInput.value, getSelectedPattern())
    // Le planning est déjà sauvegardé dans generateSchedule,
    // on charge juste les modifications précédentes
    setTimeout(() => StorageManager.loadSchedule(calendarDiv), 100)
  })

  function initialize() {
    // Charger le pattern personnalisé
    CustomPatternManager.load()

    // Charger les préférences sauvegardées
    const savedPattern = localStorage.getItem('pattern-select')
    const savedStartDate = localStorage.getItem('start-date')

    if (savedPattern) {
      patternSelect.value = savedPattern
    }

    if (savedStartDate) {
      startDateInput.value = savedStartDate
      // Générer automatiquement le calendrier si on a une date de début
      CalendarManager.generateSchedule(savedStartDate, getSelectedPattern())
      // Charger les modifications sauvegardées
      setTimeout(() => StorageManager.loadSchedule(calendarDiv), 100)
    }

    // Initialiser le textarea avec le pattern initial
    const initialPattern = getInitialPattern(patternSelect.value)
    updatePatternTextarea(initialPattern)
  }

  // Lancer l'initialisation
  initialize()
})



function setupResetButton() {
  const resetButton = document.getElementById('reset')

  if (resetButton) {
    resetButton.addEventListener('click', () => {
      const confirmation = window.confirm('Êtes-vous sûr de vouloir effacer toutes vos données sauvegardées ? Cette action est irréversible.')

      if (confirmation) {
        localStorage.clear()
        //alert('Toutes les données ont été effacées.')
        console.log(`Le localStorage a été réinitialisé.`)
        location.reload()
        console.log(`Rechargement de la page.`)
      }
    })
  }
}

document.addEventListener('DOMContentLoaded', setupResetButton)
