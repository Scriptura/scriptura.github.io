import { publicHolidays } from './publicHolidays.js'

// Fonction pour obtenir l'année en cours
function getCurrentYear() {
  return new Date().getFullYear().toString()
}

// Fonction pour vérifier si un mois appartient à l'année en cours
function isCurrentYearMonth(monthKey) {
  // Le format est "month-M-YYYY"
  const year = monthKey.split('-')[0]
  return year === getCurrentYear()
}

// Fonction pour filtrer les données de l'année en cours
function filterCurrentYearData(scheduleData) {
  const currentYearData = {}

  for (const monthKey in scheduleData) {
    if (isCurrentYearMonth(monthKey)) {
      currentYearData[monthKey] = scheduleData[monthKey]
    }
  }

  return currentYearData
}

// Fonction pour calculer les statistiques des lettres
function calculateLetterStats(scheduleData) {
  const letterStats = {}
  const currentYearData = filterCurrentYearData(scheduleData)

  // Parcourir chaque mois et chaque jour pour compter les lettres
  for (const month in currentYearData) {
    for (const day in currentYearData[month]) {
      // Récupérer la deuxième valeur [1] si elle existe, sinon prendre la première [0]
      const dayData = currentYearData[month][day]
      const letter = dayData[1] !== undefined ? dayData[1] : dayData[0]

      if (letterStats[letter]) {
        letterStats[letter]++
      } else {
        letterStats[letter] = 1
      }
    }
  }

  return letterStats
}

// Fonction pour calculer le nombre de jours travaillés sur des jours fériés ou des dimanches sur l'année en cours
function calculateHolidayAndSundayWork(scheduleData) {
  const holidays = publicHolidays(getCurrentYear())
  let workOnHolidaysAndSundays = 0
  const currentYear = getCurrentYear()

  // Convertir l'objet des jours fériés en tableau de dates au format YYYY-MM-DD
  const holidayDates = Object.values(holidays).map(date => {
    const holidayDate = new Date(date)
    // Ajouter un jour pour compenser le décalage UTC
    holidayDate.setDate(holidayDate.getDate() + 1)
    return holidayDate.toISOString().split('T')[0]
  })

  // Filtrer les données pour ne garder que l'année en cours
  const currentYearData = Object.entries(scheduleData)
    .filter(([monthKey]) => monthKey.startsWith(currentYear))
    .reduce((acc, [month, data]) => {
      acc[month] = data
      return acc
    }, {})

  // Parcourir les données du planning
  Object.entries(currentYearData).forEach(([monthKey, monthData]) => {
    // Extraire le mois depuis la clé (ex: "2024-1" -> "1")
    const month = monthKey.split('-')[1]

    Object.entries(monthData).forEach(([day, dayData]) => {
      // Vérifier si on a une deuxième lettre
      const letter = dayData[1]

      // Si pas de deuxième lettre, on passe à l'itération suivante
      if (!letter) return

      // Créer une date au format YYYY-MM-DD
      const dateString = `${currentYear}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`
      const currentDate = new Date(dateString)

      // Vérifier si c'est un dimanche
      const isSunday = currentDate.getDay() === 0

      // Vérifier si c'est un jour férié
      const isHoliday = holidayDates.includes(dateString)

      // Vérifier les conditions et incrémenter le compteur si nécessaire
      if ((isHoliday || isSunday) && ['M', 'J', 'S'].includes(letter)) {
        workOnHolidaysAndSundays++
      }
    })
  })

  return workOnHolidaysAndSundays
}

/**
 * Réorganise les données pour intercaler les grandes et petites valeurs.
 * @param {Object} stats - Objet contenant les statistiques à trier.
 * @returns {Array} Tableau réorganisé pour éviter que les petites valeurs se suivent.
 */
function rearrangeStats(stats) {
  // Convertit les stats en un tableau d'entrées et les trie par valeur décroissante
  const sortedEntries = Object.entries(stats).sort((a, b) => b[1] - a[1])

  // Divise les entrées en deux groupes : hautes et basses valeurs
  const mid = Math.ceil(sortedEntries.length / 2)
  const highValues = sortedEntries.slice(0, mid) // Grandes valeurs
  const lowValues = sortedEntries.slice(mid) // Petites valeurs

  const result = []
  const maxLength = Math.max(highValues.length, lowValues.length)

  // Intercale les groupes sans doublons
  for (let i = 0; i < maxLength; i++) {
    if (i < highValues.length) {
      result.push(highValues[i])
    }
    if (i < lowValues.length) {
      result.push(lowValues[i])
    }
  }

  return result
}

// Fonction pour mettre à jour l'affichage des statistiques dans le <output>
function updateLetterStats() {
  const scheduleData = JSON.parse(localStorage.getItem('scheduleData'))
  if (scheduleData) {
    const stats = calculateLetterStats(scheduleData)

    // Convertir les statistiques en une chaîne de texte formatée
    const rearrangedStats = rearrangeStats(stats)
    const formattedStats = rearrangedStats.map(([letter, count]) => `{"value": ${count}, "label": "${letter}"}`).join(',')

    const output = document.getElementById('stats')
    const workOnHolidaysAndSundays = calculateHolidayAndSundayWork(scheduleData) // Calculer les jours travaillés sur des jours fériés ou des dimanches.

    //output.innerHTML = `<pie-chart data='[${formattedStats}]' gap="0" donut="0.7"></pie-chart>`
    output.innerHTML = `
     <pie-chart data='[${formattedStats}]' gap="0" donut="0.7"></pie-chart>
     <p>Dimanches et jours fériés travaillés&nbsp;: <strong>${workOnHolidaysAndSundays}</strong></p>
   `
  }
}

// Code d'initialisation exécuté au chargement du DOM
document.addEventListener('DOMContentLoaded', () => {
  // Configurer le MutationObserver
  const tableObserver = new MutationObserver(mutations => {
    // Vérifier si un ajout ou une modification d'élément a eu lieu
    mutations.forEach(mutation => {
      if (mutation.type === 'childList' || mutation.type === 'attributes') {
        updateLetterStats()
      }
    })
  })

  // Options du MutationObserver pour observer les ajouts de nœuds et les changements d'attributs
  const tableConfig = {
    childList: true,
    subtree: true,
    attributes: true,
  }

  const tables = document.querySelectorAll('.table')

  // Démarrer l'observation sur chaque table
  tables.forEach(table => {
    tableObserver.observe(table, tableConfig)
  })

  // Mettre à jour les statistiques lors du chargement initial
  updateLetterStats()

  // Ajouter un écouteur sur le bouton pour mettre à jour les statistiques lors de la génération du planning
  const generateButton = document.getElementById('generate-schedule')

  if (generateButton) {
    generateButton.addEventListener('click', () => {
      updateLetterStats()
    })
  }
})
