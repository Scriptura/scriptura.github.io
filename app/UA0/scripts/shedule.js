import { publicHolidays } from './publicHolidays.js'

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

function isIphone() {
  // @bugfix Filtrage des iPhones en raison d'un bug : 0 par défaut, puis accepte la valeur 1 pour le lundi ; pas de solution pour l'instant.
  return /iPhone|iPad|iPod/i.test(navigator.userAgent)
}

/**
 * Calcule la plage de semestres à afficher en fonction de la date actuelle.
 * @returns {{ startDate: Date, endDate: Date }} - Les dates de début et de fin de la plage.
 */
function getSemesterRange() {
  const today = new Date()
  const currentYear = today.getFullYear()
  const currentMonth = today.getMonth()

  // Déterminer le semestre courant : 0 pour janvier-juin, 6 pour juillet-décembre
  const currentSemesterStartMonth = currentMonth < 6 ? 0 : 6

  // Début : un semestre avant
  const startYear = currentSemesterStartMonth === 0 ? currentYear - 1 : currentYear
  const startMonth = currentSemesterStartMonth === 0 ? 6 : 0
  const startDate = new Date(startYear, startMonth, 1)

  // Fin : deux semestres après
  const endYear = currentSemesterStartMonth === 0 ? currentYear + 1 : currentYear + 1
  const endMonth = currentSemesterStartMonth === 0 ? 6 : 12
  const endDate = new Date(endYear, endMonth, 0) // Dernier jour du mois

  return { startDate, endDate }
}

function updateScheduleData() {
  // Vérifier si `scheduleData` existe déjà
  if (!localStorage.getItem('scheduleData')) {
    console.log('Aucune donnée existante pour scheduleData. Mise à jour ignorée.')
    return
  }

  // Calculer la plage actuelle
  const { startDate, endDate } = getSemesterRange()
  const scheduleData = JSON.parse(localStorage.getItem('scheduleData')) || {}

  // Convertir les dates en identifiants de semestres au format YYYY-MM
  const currentSemesters = []
  let tempDate = new Date(startDate)
  while (tempDate <= endDate) {
    const semesterId = `${tempDate.getFullYear()}-${tempDate.getMonth() + 1}`
    currentSemesters.push(semesterId)

    // Avancer au mois suivant
    tempDate.setMonth(tempDate.getMonth() + 1)
  }

  // Étape 2 : Supprimer les semestres obsolètes
  for (const storedSemester of Object.keys(scheduleData)) {
    if (!currentSemesters.includes(storedSemester)) {
      delete scheduleData[storedSemester]
    }
  }

  // Étape 3 : Ajouter les nouveaux semestres
  for (const semesterId of currentSemesters) {
    if (!scheduleData[semesterId]) {
      // Initialiser les jours du mois avec des valeurs par défaut
      const [year, month] = semesterId.split('-').map(Number)
      const daysInMonth = new Date(year, month, 0).getDate()

      scheduleData[semesterId] = {}
      for (let day = 1; day <= daysInMonth; day++) {
        scheduleData[semesterId][day] = ['J', 'J'] // Valeur par défaut
      }
    }
  }

  // Étape 4 : Sauvegarder les données mises à jour
  localStorage.setItem('scheduleData', JSON.stringify(scheduleData))
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
  // Mise en cache des classes CSS avec Set pour éviter les recalculs
  validClasses: new Set([
    'event-day',
    'event-evening',
    'event-morning',
    'event-rest',
    'event-extra-rest',
    'event-holiday',
    'event-night',
    'event-leave',
    'event-formation',
    'event-overtime',
    'event-stop',
    'event-strike',
    'event-union',
    'event-other',
  ]),

  // Cache de correspondance entre lettres et classes
  classMap: new Map([
    ['J', 'event-day'],
    ['S', 'event-evening'],
    ['M', 'event-morning'],
    ['R', 'event-rest'],
    ['T', 'event-extra-rest'],
    ['F', 'event-holiday'],
    ['N', 'event-night'],
    ['C', 'event-leave'],
    ['I', 'event-formation'],
    ['H', 'event-overtime'],
    ['A', 'event-stop'],
    ['G', 'event-strike'],
    ['D', 'event-union'],
    ['O', 'event-other'],
  ]),

  getClass(scheduleLetter) {
    return this.classMap.get(scheduleLetter) || null
  },

  isValidClass(className) {
    return this.validClasses.has(className)
  },
}

// Gestionnaire du calendrier
const CalendarManager = {
  /**
   * Génère un planning sur une plage de semestres autour du semestre actuel.
   * @param {string} startDateInput - Date de début au format YYYY-MM-DD (facultative).
   * @param {Array<string>} selectedPattern - Motif de rotation des horaires.
   */
  async generateSchedule(startDateInput, selectedPattern) {
    if (!startDateInput) {
      alert('Veuillez entrer une date de début.')
      return
    }

    const startDate = new Date(startDateInput)
    startDate.setDate(startDate.getDate() - 1)

    const calendarDiv = document.getElementById('calendar')
    calendarDiv.innerHTML = ''

    const { startDate: displayStartDate, endDate: displayEndDate } = getSemesterRange()

    // Création du fragment pour la manipulation hors DOM
    const fragment = document.createDocumentFragment()
    const currentDate = new Date()

    // Génération des mois de manière asynchrone
    const generateMonths = async () => {
      let tempDate = new Date(displayStartDate)
      while (tempDate <= displayEndDate) {
        const monthDate = new Date(tempDate)
        const isCurrentMonth = monthDate.getMonth() === currentDate.getMonth() && monthDate.getFullYear() === currentDate.getFullYear()

        const monthIndex =
          (monthDate.getFullYear() - displayStartDate.getFullYear()) * 12 + monthDate.getMonth() - displayStartDate.getMonth()

        // Utilisation de requestAnimationFrame pour la génération des tables
        await new Promise(resolve => {
          requestAnimationFrame(() => {
            this.generateMonthTable(displayStartDate, monthIndex, startDate, selectedPattern, fragment, isCurrentMonth)
            resolve()
          })
        })

        tempDate.setMonth(tempDate.getMonth() + 1)
      }
    }

    await generateMonths()
    calendarDiv.appendChild(fragment)

    if (!localStorage.getItem('scheduleData')) {
      await StorageManager.saveSchedule(calendarDiv)
    }
  },

  /**
   * Génère le tableau HTML pour un mois spécifique
   * @param {Date} displayStartDate - Date de début d'affichage
   * @param {number} monthIndex - Index du mois (0-23)
   * @param {Date} startDate - Date de début du planning
   * @param {Array<string>} selectedPattern - Motif de rotation
   * @param {DocumentFragment} fragment - Fragment conteneur
   * @param {boolean} isCurrentMonth - Indique si c'est le mois courant
   */
  generateMonthTable(displayStartDate, monthIndex, startDate, selectedPattern, fragment, isCurrentMonth) {
    const monthDiv = document.createElement('div')
    const monthTable = document.createElement('table')
    monthTable.classList.add('table')

    const currentDate = new Date()
    const currentMonth = currentDate.getMonth()
    const currentYear = currentDate.getFullYear()

    const monthDate = new Date(displayStartDate)
    monthDate.setMonth(displayStartDate.getMonth() + monthIndex)

    const tableMonth = monthDate.getMonth()
    const tableYear = monthDate.getFullYear()

    if (isCurrentMonth) {
      monthTable.classList.add('current')
    } else if (tableYear < currentYear || (tableYear === currentYear && tableMonth < currentMonth)) {
      monthTable.classList.add('past')
    } else {
      monthTable.classList.add('future')
    }

    monthTable.id = `month-${tableMonth + 1}-${tableYear}`

    // Attribut data pour stocker le format YYYY-MM utilisé en interne
    monthTable.setAttribute('data-month-id', `${tableYear}-${tableMonth + 1}`)

    // Création d'un fragment pour les éléments de la table
    const tableFragment = document.createDocumentFragment()

    this.fillMonthTable(tableFragment, monthDate, startDate, selectedPattern)
    this.addTableCaption(monthTable, monthDate)

    // Ajout du contenu au tableau
    monthTable.appendChild(tableFragment)
    monthDiv.appendChild(monthTable)
    fragment.appendChild(monthDiv)

    if (tableYear < currentYear || (tableYear === currentYear && tableMonth < currentMonth)) {
      monthTable.parentNode.classList.add('hidden')
    }
  },

  /**
   * Ajoute l'en-tête du tableau avec les jours de la semaine
   * @param {DocumentFragment} fragment - Fragment conteneur
   * @param {Array<string>} daysOfWeek - Jours de la semaine
   */
  addTableHeader(fragment, daysOfWeek) {
    const headerRow = document.createElement('tr')
    daysOfWeek.forEach(day => {
      const th = document.createElement('th')
      th.textContent = day
      headerRow.appendChild(th)
    })
    fragment.appendChild(headerRow)
  },

  /**
   * Remplit le tableau avec les jours du mois
   * @param {DocumentFragment} fragment - Fragment conteneur
   * @param {Date} currentMonth - Mois courant
   * @param {Date} startDate - Date de début du planning
   * @param {Array<string>} selectedPattern - Motif de rotation
   */
  fillMonthTable(fragment, currentMonth, startDate, selectedPattern) {
    const firstDay = new Date(currentMonth.getFullYear(), currentMonth.getMonth(), 1)
    const lastDay = new Date(currentMonth.getFullYear(), currentMonth.getMonth() + 1, 0)
    const firstWeekday = (firstDay.getDay() + 6) % 7
    const daysInMonth = lastDay.getDate()
    const holidays = publicHolidays(currentMonth.getFullYear())
    const tableHead = document.createElement('thead')
    const tableBody = document.createElement('tbody')

    // Création de l'en-tête dans le thead
    const headerRow = document.createElement('tr')
    const weekDays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim']
    weekDays.forEach(day => {
      const th = document.createElement('th')
      th.textContent = day
      headerRow.appendChild(th)
    })
    tableHead.appendChild(headerRow)
    fragment.appendChild(tableHead)

    // Création des lignes pour le corps de la table
    const rowsFragment = document.createDocumentFragment()
    let row = document.createElement('tr')

    for (let i = 0; i < firstWeekday; i++) {
      row.appendChild(document.createElement('td'))
    }

    for (let day = 1; day <= daysInMonth; day++) {
      const currentDate = new Date(currentMonth.getFullYear(), currentMonth.getMonth(), day)
      const daysSinceStart = Math.floor((currentDate - startDate) / (1000 * 60 * 60 * 24))
      const rotationIndex = ((daysSinceStart % selectedPattern.length) + selectedPattern.length) % selectedPattern.length

      const dayCell = this.createDayCell(day, rotationIndex, selectedPattern, currentDate)
      const today = new Date()
      if (day === today.getDate() && currentMonth.getMonth() === today.getMonth() && currentMonth.getFullYear() === today.getFullYear()) {
        dayCell.classList.add('current-day')
      }

      const holidayNames = Object.entries(holidays).filter(([_, date]) => date.toDateString() === currentDate.toDateString())
      if (holidayNames.length > 0) {
        dayCell.classList.add('public-holiday')
      }

      row.appendChild(dayCell)

      if ((firstWeekday + day) % 7 === 0) {
        rowsFragment.appendChild(row)
        row = document.createElement('tr')
      }
    }

    if (row.children.length > 0) {
      while (row.children.length < 7) {
        row.appendChild(document.createElement('td'))
      }
      rowsFragment.appendChild(row)
    }

    tableBody.appendChild(rowsFragment)
    fragment.appendChild(tableBody)
  },

  /**
   * Crée une cellule pour un jour spécifique
   * @param {number} day - Jour du mois
   * @param {number} rotationIndex - Index dans le motif de rotation
   * @param {Array<string>} selectedPattern - Motif de rotation
   * @returns {HTMLTableCellElement} Cellule du jour
   */
  createDayCell(day, rotationIndex, selectedPattern, currentDate) {
    const dayCell = document.createElement('td')
    dayCell.setAttribute('data-day', day)

    // Vérifier si c'est un dimanche (0 = dimanche dans getDay())
    const isDomingo = currentDate.getDay() === 0
    if (isDomingo) {
      dayCell.classList.add('sunday')
    }

    if (rotationIndex !== null && selectedPattern[rotationIndex]) {
      const scheduleLetter = selectedPattern[rotationIndex]
      dayCell.textContent = scheduleLetter
      dayCell.setAttribute('data-original-value', scheduleLetter)

      const className = ScheduleClassManager.getClass(scheduleLetter)
      if (className) {
        dayCell.classList.add(className)
      }
    }

    return dayCell
  },

  /**
   * Ajoute la légende du tableau avec le mois et l'année
   * @param {HTMLTableElement} table - Table du mois
   * @param {Date} currentMonth - Mois courant
   */
  addTableCaption(table, currentMonth) {
    const caption = document.createElement('caption')
    caption.textContent = currentMonth
      .toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' })
      .replace(/^\p{CWU}/u, char => char.toLocaleUpperCase('fr-FR'))
    //caption.classList.add('text-center')
    table.prepend(caption)
  },
}

// Gestionnaire de stockage local
const StorageManager = {
  scheduleData: {}, // Chargement des données en mémoire

  // Initialise les données de planning en mémoire à partir de localStorage.
  async initSchedule() {
    try {
      const data = localStorage.getItem('scheduleData')
      this.scheduleData = data ? JSON.parse(data) : {}
    } catch (error) {
      console.error("Erreur lors de l'initialisation des données:", error)
      this.scheduleData = {}
    }
  },

  // Sauvegarde les modifications du planning dans localStorage à partir du DOM.
  async saveSchedule(calendarDiv) {
    // Utilisation de requestAnimationFrame pour éviter le blocage du thread principal
    return new Promise(resolve => {
      requestAnimationFrame(() => {
        const tables = calendarDiv.querySelectorAll('table[id^="month-"]')

        tables.forEach(table => {
          const monthId = table.getAttribute('data-month-id')
          const cells = table.querySelectorAll('td[data-day]')

          cells.forEach(cell => {
            const day = cell.getAttribute('data-day')
            const value = cell.textContent.trim().toUpperCase()

            if (!this.scheduleData[monthId]) {
              this.scheduleData[monthId] = {}
            }

            const [originalValue, currentValue] = this.scheduleData[monthId][day] || [value, value]

            if (value) {
              if (value !== originalValue && value !== currentValue) {
                this.scheduleData[monthId][day] = [originalValue, value]
              } else {
                this.scheduleData[monthId][day] = [originalValue, currentValue]
              }
            }
          })
        })

        localStorage.setItem('scheduleData', JSON.stringify(this.scheduleData))
        resolve()
      })
    })
  },

  async loadSchedule(calendarDiv) {
    try {
      return new Promise(resolve => {
        requestAnimationFrame(() => {
          const savedData = this.scheduleData
          if (!savedData) {
            resolve()
            return
          }

          Object.entries(savedData).forEach(([monthId, monthData]) => {
            let [year, month] = monthId.split('-')
            const tableId = `month-${month}-${year}`
            const table = document.getElementById(tableId)
            if (!table) return

            Object.entries(monthData).forEach(([day, values]) => {
              const cell = table.querySelector(`td[data-day="${day}"]`)
              if (cell) {
                const [originalValue, currentValue] = values
                const displayValue = currentValue || originalValue

                const isSunday = cell.classList.contains('sunday')
                const isCurrentDay = cell.classList.contains('current-day')

                Array.from(cell.classList).forEach(cls => {
                  if (['modified', 'modified-spot'].includes(cls) || cls.startsWith('event-')) {
                    cell.classList.remove(cls)
                  }
                })

                cell.textContent = displayValue
                const className = ScheduleClassManager.getClass(displayValue)
                if (className) {
                  cell.classList.add(className)
                }

                if (currentValue && currentValue !== originalValue) {
                  cell.classList.add('modified')
                }

                if (isSunday) cell.classList.add('sunday')
                if (isCurrentDay) cell.classList.add('current-day')
              }
            })
          })
          resolve()
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
  editableCells: [], // Cache des cellules modifiables

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

  toggleHistory(historyButton) {
    const tables = document.querySelectorAll('.table.past')
    const tableContainers = document.querySelectorAll(':has(>.table.past)')
    const [historyText, disableHistoryText] = historyButton.querySelectorAll('span')

    if (!tables.length) {
      alert(`Veuillez d'abord générer le planning.`)
      return
    }

    tableContainers.forEach(tableContainer => {
      tableContainer.classList.toggle('hidden')
    })
    historyButton.classList.toggle('active')
    historyText.classList.toggle('hidden')
    disableHistoryText.classList.toggle('hidden')
  },

  enableEditing(calendarDiv) {
    this.editableCells = Array.from(calendarDiv.querySelectorAll('td[data-day]'))
    this.editableCells.forEach(cell => {
      cell.style.cursor = 'pointer'
      cell.setAttribute('tabindex', '0')
      cell.setAttribute('contenteditable', 'true')
    })
  },

  disableEditing(calendarDiv) {
    this.editableCells.forEach(cell => {
      cell.style.cursor = ''
      cell.removeAttribute('tabindex')
      cell.removeAttribute('contenteditable')
    })
    this.editableCells = [] // Réinitialisation du cache
    StorageManager.saveSchedule(calendarDiv)
  },

  handleCellClick(e, calendarDiv) {
    if (!this.isEditingEnabled) return

    const cell = e.target.closest('td[data-day]')
    if (cell) {
      //cell.setAttribute('contenteditable', 'true')
      cell.focus()

      // Créer un Range pour sélectionner tout le contenu de la cellule ; @note cell.select() ne fonctionne pas correctement dans ce cas de figure.
      const range = document.createRange()
      range.selectNodeContents(cell)

      // Obtenir la sélection actuelle et appliquer le range
      const selection = window.getSelection()
      selection.removeAllRanges()
      selection.addRange(range)

      // Sauvegarder la valeur courante
      cell.setAttribute('data-current-value', cell.textContent.trim())
    }
  },

  handleCellInput(e, calendarDiv) {
    if (!this.isEditingEnabled) return

    const cell = e.target.closest('td[data-day]')
    if (!cell) return

    //cell.removeAttribute('contenteditable')
    //cell.removeAttribute('tabindex')

    const value = cell.textContent.trim().toUpperCase()
    if (value.length > 1) {
      cell.textContent = value.charAt(0)
    } else {
      cell.textContent = value // Assure que la cellule affiche toujours en majuscules
    }

    if (value !== cell.getAttribute('data-original-value')) {
      cell.classList.add('modified')
    }
  },

  handleCellBlur(e, calendarDiv) {
    if (!this.isEditingEnabled) return

    const cell = e.target.closest('td[data-day]')
    if (!cell) return

    const newValue = cell.textContent.trim().toUpperCase()
    const day = cell.getAttribute('data-day')
    const monthId = cell.closest('table')?.getAttribute('data-month-id')

    // Obtenir les valeurs originales et actuelles depuis scheduleData
    const [originalValue, currentValue] = StorageManager.scheduleData[monthId]?.[day] || [null, null]

    // Empêcher les valeurs vides, nulles ou identiques
    if (!newValue) {
      cell.textContent = currentValue || originalValue // Restaurer la valeur précédente
      return
    }

    // Valider la nouvelle valeur avec les lettres autorisées
    const validLetters = ['M', 'J', 'S', 'N', 'H', 'R', 'T', 'F', 'C', 'I', 'A', 'G', 'D', 'E', 'O']
    if (!validLetters.includes(newValue)) {
      cell.textContent = currentValue || originalValue // Restaurer si non valide
      return
    }

    // Appliquer les modifications immédiates
    cell.textContent = newValue

    // Manipuler uniquement les classes dynamiques
    const className = ScheduleClassManager.getClass(newValue)
    if (className) {
      // Supprimer les classes dynamiques existantes et appliquer la nouvelle classe
      Array.from(cell.classList).forEach(cls => {
        if (cls.startsWith('event-') || cls === 'modified' || cls === 'modified-spot') {
          cell.classList.remove(cls)
        }
      })
      cell.classList.add(className)
    }

    // Gestion des classes CSS liées aux modifications
    if (newValue !== originalValue) {
      cell.classList.add('modified-spot')
    } else {
      cell.classList.remove('modified-spot')
    }

    if (newValue === originalValue) {
      cell.classList.remove('modified')
      StorageManager.scheduleData[monthId][day] = [originalValue, originalValue]
    } else {
      cell.classList.add('modified')
      StorageManager.scheduleData[monthId][day] = [originalValue, newValue]
    }

    // Sauvegarder les modifications
    StorageManager.saveSchedule(calendarDiv)
  },
}

// Initialisation et gestionnaires d'événements
document.addEventListener('DOMContentLoaded', async () => {
  // Initialiser les données de stockage local
  await StorageManager.initSchedule()

  // Mettre à jour les données du planning
  updateScheduleData()

  const calendarDiv = document.getElementById('calendar')
  const editableButton = document.getElementById('contenteditable')
  const historyButton = document.getElementById('history')
  const patternSelect = document.getElementById('pattern-select')
  const startDateInput = document.getElementById('start-date')
  const customPatternTextarea = document.getElementById('custom-pattern')
  const saveCustomPatternButton = document.getElementById('save-custom-pattern')
  const generateButton = document.getElementById('generate-schedule')
  const resetButton = document.getElementById('reset')

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

  // Charger la date de début sauvegardée (si elle existe)
  const savedStartDate = localStorage.getItem('startDate')

  if (savedStartDate) {
    // Générer le calendrier avec les données existantes
    await CalendarManager.generateSchedule(savedStartDate, getSelectedPattern())
    // Charger les modifications sauvegardées
    await StorageManager.loadSchedule(calendarDiv)
  }

  // Initialiser le textarea avec le pattern sélectionné
  const initialPattern = getInitialPattern(patternSelect.value)
  updatePatternTextarea(initialPattern)

  if (editableButton) {
    editableButton.addEventListener('click', () => {
      EditManager.toggleEditing(calendarDiv, editableButton)
    })
  }

  if (historyButton) {
    historyButton.addEventListener('click', () => {
      EditManager.toggleHistory(historyButton)
    })
  }

  if (calendarDiv) {
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
  }

  // Gestionnaire d'événement pour le changement de pattern
  patternSelect.addEventListener('change', function () {
    const initialPattern = getInitialPattern(this.value)
    updatePatternTextarea(initialPattern)
    localStorage.setItem('patternSelect', this.value)
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
  startDateInput.addEventListener('blur', function () {
    if (!this.value) {
      return
    }

    if (isIphone()) {
      return // @todo Solution à revoir.
    }

    const selectedDate = new Date(this.value)

    if (isNaN(selectedDate.getTime())) {
      alert(`Date invalide. Veuillez réessayer.`)
      this.value = ''
      return
    }

    const day = selectedDate.getDay() // .getUTCDay()

    // Vérifiez si le jour sélectionné est un lundi
    if (day !== 1) {
      alert(`Veuillez sélectionner un lundi.`)
      this.value = ''
    } else {
      localStorage.setItem('startDate', this.value)
    }
  })

  // Gestionnaire d'événement pour la génération du planning
  generateButton.addEventListener('click', async () => {
    await CalendarManager.generateSchedule(startDateInput.value, getSelectedPattern())
    await StorageManager.loadSchedule(calendarDiv)
  })

  if (resetButton) {
    resetButton.addEventListener('click', () => {
      const confirmation = window.confirm(
        'Êtes-vous sûr de vouloir effacer toutes vos données sauvegardées ? Cette action est irréversible.',
      )

      if (confirmation) {
        localStorage.clear()
        console.log(`Le localStorage a été réinitialisé.`)
        location.reload()
        console.log(`Rechargement de la page.`)
      }
    })
  }

  async function initialize() {
    // Charger le pattern personnalisé
    CustomPatternManager.load()

    // Charger les préférences sauvegardées
    const savedPattern = localStorage.getItem('patternSelect')
    const savedStartDate = localStorage.getItem('startDate')

    if (savedPattern) {
      patternSelect.value = savedPattern
    }

    if (savedStartDate) {
      startDateInput.value = savedStartDate
      // Générer automatiquement le calendrier si on a une date de début
      await CalendarManager.generateSchedule(savedStartDate, getSelectedPattern())
      // Charger les modifications sauvegardées
      await StorageManager.loadSchedule(calendarDiv)
    }

    // Initialiser le textarea avec le pattern initial
    const initialPattern = getInitialPattern(patternSelect.value)
    updatePatternTextarea(initialPattern)
  }

  await initialize()
})
