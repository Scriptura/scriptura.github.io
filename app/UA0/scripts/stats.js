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

// Fonction pour mettre à jour l'affichage des statistiques dans le <output>
function updateLetterStats() {
  const scheduleData = JSON.parse(localStorage.getItem('scheduleData'))
  if (scheduleData) {
    const stats = calculateLetterStats(scheduleData)

    // Convertir les statistiques en une chaîne de texte formatée
    const formattedStats = Object.entries(stats)
      .map(
        ([letter, count]) =>
          `{"value": ${count}, "label": "${letter} ${count}"}`,
      )
      .join(',')

    const output = document.getElementById('stats')
    output.innerHTML = `<pie-chart data='[${formattedStats}]'></pie-chart>`
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
