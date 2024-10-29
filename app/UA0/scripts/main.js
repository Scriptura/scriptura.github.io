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
      const registration = await navigator.serviceWorker.register('/app/UA0/serviceWorker.js')

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

// Script pour le planning :

// prettier-ignore
const rotationPatternIDE = [
  'J', 'J', 'S', 'J', 'J', 'R', 'R',
  'S', 'S', 'J', 'M', 'F', 'R', 'R',
  'S', 'S', 'M', 'M', 'R', 'S', 'S',
  'J', 'M', 'R', 'R', 'T', 'M', 'M',
  'M', 'R', 'J', 'S', 'S', 'R', 'R',
  'J', 'J', 'S', 'J', 'M', 'R', 'R',
  'S', 'S', 'J', 'J', 'M', 'R', 'R',
  'F', 'S', 'S', 'J', 'J', 'R', 'R',
  'M', 'M', 'M', 'R', 'S', 'S', 'S',
  'T', 'R', 'R', 'S', 'J', 'M', 'M',
  'R', 'J', 'J', 'S', 'S', 'R', 'R',
]

// prettier-ignore
const rotationPatternNightIDE = [
  'N', 'N', 'R', 'R', 'N', 'N', 'N',
  'R', 'R', 'N', 'N', 'R', 'R', 'R',
]

// prettier-ignore
const rotationPatternASH = [
  'M', 'M', 'M', 'M', 'R', 'S', 'S',
  'S', 'S', 'R', 'R', 'M', 'M', 'M',
  'M', 'R', 'S', 'S', 'S', 'R', 'R',
  'T', 'M', 'M', 'M', 'M', 'R', 'R',
]

// Fonction pour obtenir le modèle sélectionné
function getSelectedPattern() {
  const selectedPattern = document.getElementById('pattern-select').value

  if (selectedPattern === 'NightIDE') {
    return rotationPatternNightIDE
  }

  if (selectedPattern === 'ASH') {
    return rotationPatternASH
  }

  return rotationPatternIDE
}

// Enregistrement dans localStorage au changement du champ pattern-select
document.getElementById('pattern-select').addEventListener('change', function () {
  localStorage.setItem('pattern-select', this.value)
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

// Récupération des valeurs au chargement complet de la page
window.onload = () => {
  const savedPattern = localStorage.getItem('pattern-select')
  const savedStartDate = localStorage.getItem('start-date')

  if (savedPattern) {
    document.getElementById('pattern-select').value = savedPattern
  }

  if (savedStartDate) {
    document.getElementById('start-date').value = savedStartDate
  }
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
      const rotationIndex = daysSinceStart >= 0 ? daysSinceStart % selectedPattern.length : (selectedPattern.length + daysSinceStart % selectedPattern.length) % selectedPattern.length

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

;(function addPrintEventListener() {
  const printButtons = document.querySelectorAll('.cmd-print')

  for (const printButton of printButtons) {
    printButton.onclick = function () {
      window.print()
    }
  }
})()
