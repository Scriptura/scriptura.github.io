// prettier-ignore
const rotationPatternIDE = [
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
const rotationPatternNightIDE = [
  'N', 'N', 'R', 'R', 'N', 'N', 'N',
  'R', 'R', 'N', 'N', 'R', 'R', 'R',
];

// prettier-ignore
const rotationPatternASH = [
  'M', 'M', 'M', 'M', 'R', 'S', 'S',
  'S', 'S', 'R', 'R', 'M', 'M', 'M',
  'M', 'R', 'S', 'S', 'S', 'R', 'R',
  'T', 'M', 'M', 'M', 'M', 'R', 'R',
];

// Initialisation du pattern personnalisé
let rotationPatternCustom = []

// Fonction pour formater le pattern pour l'affichage (groupes de 7 avec retours à la ligne)
function formatPatternForDisplay(pattern) {
  // Si le pattern est un tableau, le convertir en string
  const patternString = Array.isArray(pattern) ? pattern.join(',') : pattern

  // Découper le string en tableau, nettoyer les éléments
  const elements = patternString.split(',').map(el => el.trim())

  // Regrouper par 7 (une semaine)
  const weeks = []
  for (let i = 0; i < elements.length; i += 7) {
    const week = elements.slice(i, i + 7)
    // Ajouter des espaces après les virgules sauf pour le dernier élément de la semaine
    weeks.push(week.join(', '))
  }

  // Joindre les semaines avec des retours à la ligne
  return weeks.join(',\n')
}

// Fonction pour nettoyer et normaliser l'entrée utilisateur
function cleanPatternInput(input) {
  return (
    input
      // Convertir en majuscules
      .toUpperCase()
      // Supprimer tous les espaces, tabulations et retours à la ligne
      .replace(/[\s\n\r\t]/g, '')
      // Supprimer les virgules multiples
      .replace(/,+/g, ',')
      // Supprimer la virgule au début si elle existe
      .replace(/^,/, '')
      // Supprimer la virgule à la fin si elle existe
      .replace(/,$/, '')
  )
}

// Fonction pour valider le pattern
function validatePattern(pattern) {
  const validChars = ['J', 'S', 'M', 'R', 'T', 'F', 'N']
  const patternArray = pattern.split(',')

  for (let char of patternArray) {
    char = char.trim()
    if (!validChars.includes(char)) {
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
      return rotationPatternNightIDE
    case 'ASH':
      return rotationPatternASH
    case 'CUSTOM':
      // Si un pattern personnalisé existe, l'utiliser
      if (rotationPatternCustom.length > 0) {
        return rotationPatternCustom
      }
      // Sinon, essayer de charger depuis localStorage
      const savedCustomPattern = localStorage.getItem('rotation-pattern-custom')
      if (savedCustomPattern) {
        rotationPatternCustom = JSON.parse(savedCustomPattern)
        return rotationPatternCustom
      }
      return rotationPatternIDE
    default:
      return rotationPatternIDE
  }
}

// Fonction pour mettre à jour le textarea avec le pattern sélectionné
function updatePatternTextarea(pattern) {
  const textarea = document.getElementById('pattern-custom')
  textarea.value = formatPatternForDisplay(pattern)
}

// Fonction pour convertir une chaîne en tableau
function stringToPattern(str) {
  return cleanPatternInput(str).split(',')
}

// Modification de la fonction getSelectedPattern pour utiliser le textarea
function getSelectedPattern() {
  const customPattern = document.getElementById('pattern-custom').value
  return stringToPattern(customPattern)
}

// Écouteur d'événement pour le changement de pattern
document.getElementById('pattern-select').addEventListener('change', function () {
  const initialPattern = getInitialPattern(this.value)
  updatePatternTextarea(initialPattern)
  localStorage.setItem('pattern-select', this.value)
})

// Écouteur d'événement pour la sauvegarde du pattern personnalisé
document.getElementById('pattern-custom').addEventListener('blur', function () {
  const cleanedValue = cleanPatternInput(this.value)
  if (validatePattern(cleanedValue)) {
    // Reformater le texte pour l'affichage
    this.value = formatPatternForDisplay(cleanedValue)

    // Si le select est sur "CUSTOM", mettre à jour rotationPatternCustom
    const selectElement = document.getElementById('pattern-select')
    if (selectElement.value === 'CUSTOM') {
      rotationPatternCustom = stringToPattern(cleanedValue)
      localStorage.setItem('rotation-pattern-custom', JSON.stringify(rotationPatternCustom))
    }
  } else {
    // En cas d'erreur, restaurer la dernière valeur valide selon le type sélectionné
    const selectElement = document.getElementById('pattern-select')
    if (selectElement.value === 'CUSTOM' && rotationPatternCustom.length > 0) {
      this.value = formatPatternForDisplay(rotationPatternCustom)
    } else {
      // Si pas de pattern personnalisé, revenir au pattern initial
      const initialPattern = getInitialPattern(selectElement.value)
      this.value = formatPatternForDisplay(initialPattern)
    }
  }
})

// Enregistrement dans localStorage au changement du champ start-date
document.getElementById('start-date').addEventListener('change', function () {
  const selectedDate = new Date(this.value)
  const day = selectedDate.getDay()

  // Vérifier si le jour sélectionné n'est pas un lundi
  if (day !== 1) {
    alert('Veuillez sélectionner un lundi.')
    this.value = '' // Réinitialiser le champ
  } else {
    localStorage.setItem('start-date', this.value)
  }
})

// Chargement initial
window.onload = () => {
  // Charger le pattern personnalisé depuis localStorage s'il existe
  const savedCustomPattern = localStorage.getItem('rotation-pattern-custom')
  if (savedCustomPattern) {
    rotationPatternCustom = JSON.parse(savedCustomPattern)
  }

  const savedPattern = localStorage.getItem('pattern-select')
  const savedStartDate = localStorage.getItem('start-date')

  if (savedPattern) {
    document.getElementById('pattern-select').value = savedPattern
  }

  if (savedStartDate) {
    document.getElementById('start-date').value = savedStartDate
  }

  // Initialiser le textarea avec le pattern approprié
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
  startDate.setDate(startDate.getDate() - 1) // Ajuster d'un jour en avance
  const calendarDiv = document.getElementById('calendar')
  calendarDiv.innerHTML = ''

  const daysOfWeek = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim']

  // Calculer la date de début d'affichage
  const displayStartDate = new Date()
  displayStartDate.setDate(1) // Fixer au premier jour du mois courant

  for (let monthIndex = 0; monthIndex < 24; monthIndex++) {
    const monthDiv = document.createElement('div')
    const monthTable = document.createElement('table')
    monthTable.classList.add('table')

    const headerRow = document.createElement('tr')
    daysOfWeek.forEach(day => {
      const th = document.createElement('th')
      th.textContent = day
      headerRow.appendChild(th)
    })
    monthTable.appendChild(headerRow)

    const currentMonth = new Date(displayStartDate)
    currentMonth.setMonth(displayStartDate.getMonth() + monthIndex)

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

  // Ajouter la classe .ready au bouton d'impression
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
