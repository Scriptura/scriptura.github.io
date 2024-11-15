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

// Fonction pour calculer les statistiques
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
    output.innerHTML = `<pie-chart data='[${formattedStats}]' gap="0" donut="0.7"></pie-chart>`
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

  // Sélectionner toutes les tables avec la classe '.table'
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
