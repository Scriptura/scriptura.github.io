// prettier-ignore
const rotationIDEPattern = [
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
];

// prettier-ignore
const rotationNightIDEPattern = [
  'N', 'N', 'R', 'R', 'N', 'N', 'N',
  'R', 'R', 'N', 'N', 'R', 'R', 'R',
];

// prettier-ignore
const rotationASHPattern = [
  'M', 'M', 'M', 'M', 'R', 'S', 'S',
  'S', 'S', 'R', 'R', 'M', 'M', 'M',
  'M', 'R', 'S', 'S', 'S', 'R', 'R',
  'T', 'M', 'M', 'M', 'M', 'R', 'R',
];

// Initialisation du pattern personnalisé
let rotationCustomPattern = []

// Fonction pour formater le pattern pour l'affichage (groupes de 7 avec retours à la ligne)
function formatPatternForDisplay(pattern) {
  const patternString = Array.isArray(pattern) ? pattern.join(',') : pattern
  const elements = patternString.split(',').map(el => el.trim())

  const weeks = []
  for (let i = 0; i < elements.length; i += 7) {
    const week = elements.slice(i, i + 7)
    weeks.push(week.join(', '))
  }
  return weeks.join(',\n')
}

// Fonction pour nettoyer et normaliser l'entrée utilisateur
function cleanPatternInput(input) {
  return input
    .toUpperCase()
    .replace(/[\s\n\r\t]/g, '')
    .replace(/,+/g, ',')
    .replace(/^,/, '')
    .replace(/,$/, '')
}

// Fonction pour valider le pattern
function validatePattern(pattern) {
  if (!pattern.trim()) {
    return true
  }

  const validChars = ['J', 'S', 'M', 'R', 'T', 'F', 'N']
  const patternArray = pattern.split(',')

  for (let char of patternArray) {
    char = char.trim()
    if (char && !validChars.includes(char)) {
      alert(`Caractère invalide détecté : "${char}"\nSeuls les caractères suivants sont autorisés : J, S, M, R, T, F, N`)
      return false
    }
  }
  return true
}

// Fonction pour obtenir le pattern initial selon la sélection
function getInitialPattern(patternType) {
  switch (patternType) {
    case 'NightIDE':
      return rotationNightIDEPattern
    case 'ASH':
      return rotationASHPattern
    case 'CUSTOM':
      if (rotationCustomPattern.length > 0) {
        return rotationCustomPattern
      }
      const savedCustomPattern = localStorage.getItem('rotation-custom-pattern')
      if (savedCustomPattern) {
        rotationCustomPattern = JSON.parse(savedCustomPattern)
        return rotationCustomPattern
      }
      return rotationIDEPattern
    default:
      return rotationIDEPattern
  }
}

// Fonction pour mettre à jour le textarea avec le pattern sélectionné
function updatePatternTextarea(pattern) {
  const textarea = document.getElementById('custom-pattern')
  textarea.value = formatPatternForDisplay(pattern)
}

// Fonction pour convertir une chaîne en tableau
function stringToPattern(str) {
  return !str.trim() ? [] : cleanPatternInput(str).split(',')
}

// Modification de la fonction getSelectedPattern pour utiliser le textarea
function getSelectedPattern() {
  const customPattern = document.getElementById('custom-pattern').value
  return stringToPattern(customPattern)
}

// Écouteur d'événement pour le changement de pattern
document.getElementById('pattern-select').addEventListener('change', function () {
  const initialPattern = getInitialPattern(this.value)
  updatePatternTextarea(initialPattern)
  localStorage.setItem('pattern-select', this.value)
})

// Écouteur d'événement pour la sauvegarde du pattern personnalisé
document.querySelector('.save-custom-pattern').addEventListener('click', function () {
  const patternInput = document.getElementById('custom-pattern')
  const cleanedValue = cleanPatternInput(patternInput.value)

  if (validatePattern(cleanedValue)) {
    patternInput.value = formatPatternForDisplay(cleanedValue)
    rotationCustomPattern = stringToPattern(cleanedValue)
    localStorage.setItem('rotation-custom-pattern', JSON.stringify(rotationCustomPattern))
  } else {
    if (rotationCustomPattern.length > 0) {
      patternInput.value = formatPatternForDisplay(rotationCustomPattern)
    } else {
      const selectElement = document.getElementById('pattern-select')
      const initialPattern = getInitialPattern(selectElement.value)
      patternInput.value = formatPatternForDisplay(initialPattern)
    }
  }
})

// Enregistrement dans localStorage au changement du champ start-date
document.getElementById('start-date').addEventListener('change', function () {
  const selectedDate = new Date(this.value)
  const day = selectedDate.getDay()

  if (day !== 1) {
    alert('Veuillez sélectionner un lundi.')
    this.value = ''
  } else {
    localStorage.setItem('start-date', this.value)
  }
})

// Chargement initial
window.onload = () => {
  const savedCustomPattern = localStorage.getItem('rotation-custom-pattern')
  if (savedCustomPattern) {
    rotationCustomPattern = JSON.parse(savedCustomPattern)
  }

  const savedPattern = localStorage.getItem('pattern-select')
  const savedStartDate = localStorage.getItem('start-date')

  if (savedPattern) {
    document.getElementById('pattern-select').value = savedPattern
  }

  if (savedStartDate) {
    document.getElementById('start-date').value = savedStartDate
  }

  const initialPattern = getInitialPattern(document.getElementById('pattern-select').value)
  updatePatternTextarea(initialPattern)
}

function generateSchedule() {
  const startDateInput = document.getElementById('start-date').value
  if (!startDateInput) {
    alert('Veuillez entrer une date de début.')
    return
  }

  const selectedPattern = getSelectedPattern()
  const startDate = new Date(startDateInput)
  startDate.setDate(startDate.getDate() - 1)
  const calendarDiv = document.getElementById('calendar')
  calendarDiv.innerHTML = ''

  const daysOfWeek = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim']

  const displayStartDate = new Date()
  displayStartDate.setDate(1)

  for (let monthIndex = 0; monthIndex < 24; monthIndex++) {
    const monthDiv = document.createElement('div')
    const monthTable = document.createElement('table')
    monthTable.classList.add('table')

    // Ajouter l'ID basé sur le mois et l'année, avec un préfixe pour éviter un début par un chiffre
    const currentMonth = new Date(displayStartDate)
    currentMonth.setMonth(displayStartDate.getMonth() + monthIndex)

    const monthYearId = `month-${currentMonth.getMonth() + 1}-${currentMonth.getFullYear()}`
    monthTable.id = monthYearId

    const headerRow = document.createElement('tr')
    daysOfWeek.forEach(day => {
      const th = document.createElement('th')
      th.textContent = day
      headerRow.appendChild(th)
    })
    monthTable.appendChild(headerRow)

    const firstDay = new Date(currentMonth.getFullYear(), currentMonth.getMonth(), 1)
    const lastDay = new Date(currentMonth.getFullYear(), currentMonth.getMonth() + 1, 0)
    const firstWeekday = (firstDay.getDay() + 6) % 7
    const daysInMonth = lastDay.getDate()

    let row = document.createElement('tr')

    for (let i = 0; i < firstWeekday; i++) {
      const emptyCell = document.createElement('td')
      row.appendChild(emptyCell)
    }

    for (let day = 1; day <= daysInMonth; day++) {
      const currentDate = new Date(currentMonth.getFullYear(), currentMonth.getMonth(), day)
      const daysSinceStart = Math.floor((currentDate - startDate) / (1000 * 60 * 60 * 24))
      const rotationIndex =
        daysSinceStart >= 0
          ? daysSinceStart % selectedPattern.length
          : (selectedPattern.length + (daysSinceStart % selectedPattern.length)) % selectedPattern.length

      const dayCell = document.createElement('td')
      dayCell.setAttribute('data-day', day)

      if (rotationIndex !== null && selectedPattern[rotationIndex]) {
        const scheduleLetter = selectedPattern[rotationIndex]
        dayCell.textContent = scheduleLetter

        const className = getClassFromSchedule(scheduleLetter)
        if (className) {
          dayCell.classList.add(className)
        }
      } else {
        dayCell.textContent = ''
      }

      row.appendChild(dayCell)

      if ((firstWeekday + day) % 7 === 0) {
        monthTable.appendChild(row)
        row = document.createElement('tr')
      }
    }

    while (row.children.length < 7) {
      const emptyCell = document.createElement('td')
      row.appendChild(emptyCell)
    }

    monthTable.appendChild(row)

    const caption = document.createElement('caption')
    caption.textContent = currentMonth
      .toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' })
      .replace(/^\p{CWU}/u, char => char.toLocaleUpperCase('fr-FR'))
    caption.classList.add('text-center')
    monthTable.prepend(caption)

    monthDiv.appendChild(monthTable)
    calendarDiv.appendChild(monthDiv)
  }

  const printButton = document.querySelector('.cmd-print')
  printButton.classList.add('ready')
}

// Fonction pour obtenir la classe en fonction de la lettre du planning
function getClassFromSchedule(scheduleLetter) {
  switch (scheduleLetter) {
    case 'J':
      return 'event-day'
    case 'S':
      return 'event-evening'
    case 'M':
      return 'event-morning'
    case 'R':
      return 'event-rest'
    case 'T':
      return 'event-extra-rest'
    case 'F':
      return 'event-holiday'
    case 'N':
      return 'event-night'
    default:
      return null
  }
}

document.querySelector('.generate-schedule').addEventListener('click', () => {
  generateSchedule()
})
