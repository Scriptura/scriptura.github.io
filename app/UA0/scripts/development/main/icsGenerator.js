// Configuration centralisée
const ICS_CONFIG = {
  MAX_FUTURE_YEARS: 1,
  PRODUCT_ID: '-//ScripturaUA0//ICS Generator v1.0//FR',
  STORAGE_KEY: 'scheduleData',
  EVENT_DESCRIPTIONS: {
    M: 'Poste du matin',
    S: 'Poste du soir',
    J: 'Poste de journée',
    N: 'Poste de nuit',
    H: 'Heures supplémentaires',
    R: 'Repos',
    T: 'Réduction du temps de travail',
    F: 'Repos férié',
    C: 'Congé annuel',
    I: 'Formation',
    A: 'Arrêt de travail ou maladie',
    G: 'Grève',
    D: 'Décharge syndicale',
    X: 'Événement à personnaliser',
    Y: 'Événement à personnaliser',
    Z: 'Événement à personnaliser',
  },
  EVENT_SUMMARIES: {
    M: 'M',
    S: 'S',
    J: 'J',
    N: 'N',
    H: 'H sup',
    R: 'RH',
    T: 'RTT',
    F: 'RF',
    C: 'CA',
    I: 'Formation',
    A: 'Arrêt',
    G: 'Grève',
    D: 'DS',
    X: 'X',
    Y: 'Y',
    Z: 'Z',
  },
  DEFAULT_DESCRIPTION: 'Événement inconnu',
  DEFAULT_SUMMARY: '',
}

// Fonction de validation des données
function validateScheduleData(data) {
  if (!data || typeof data !== 'object') {
    throw new Error('Données de planning invalides')
  }
  return Object.keys(data).length > 0
}

// Fonction de formatage de date pour ICS
function formatDateToICS(date) {
  return date.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z'
}

// Génération et téléchargement du fichier ICS
async function generateIcsFile() {
  try {
    // Récupération des données
    const scheduleDataRaw = localStorage.getItem(ICS_CONFIG.STORAGE_KEY)
    if (!scheduleDataRaw) {
      throw new Error('Aucune donnée de planning trouvée')
    }

    const scheduleData = JSON.parse(scheduleDataRaw)

    // Validation des données
    if (!validateScheduleData(scheduleData)) {
      throw new Error('Les données de planning sont vides')
    }

    // Préparation des dates
    const now = new Date()
    const maxDate = new Date(now)
    maxDate.setFullYear(maxDate.getFullYear() + ICS_CONFIG.MAX_FUTURE_YEARS)

    const currentYear = now.getFullYear()
    const currentMonth = now.getMonth() + 1

    // Génération du contenu ICS
    let icsContent = `BEGIN:VCALENDAR
VERSION:2.0
PRODID:${ICS_CONFIG.PRODUCT_ID}
`

    // Tri et filtrage des événements
    const sortedKeys = Object.keys(scheduleData).sort()

    sortedKeys.forEach(monthKey => {
      const [year, month] = monthKey.split('-').map(Number)

      // Vérification de la pertinence de l'année et du mois
      if (year > currentYear || (year === currentYear && month >= currentMonth)) {
        const days = scheduleData[monthKey]

        Object.entries(days).forEach(([day, shifts]) => {
          const eventDate = new Date(year, month - 1, Number(day))

          // Inclusion uniquement des dates dans la fenêtre autorisée
          if (eventDate >= now && eventDate <= maxDate) {
            const eventName = shifts[1] // Priorité à la deuxième lettre

            if (eventName) {
              const eventSummary = ICS_CONFIG.EVENT_SUMMARIES[eventName] || ICS_CONFIG.DEFAULT_SUMMARY
              const eventDescription = ICS_CONFIG.EVENT_DESCRIPTIONS[eventName] || ICS_CONFIG.DEFAULT_DESCRIPTION

              const yearStr = eventDate.getFullYear()
              const monthStr = (eventDate.getMonth() + 1).toString().padStart(2, '0')
              const dayStr = eventDate.getDate().toString().padStart(2, '0')

              // @note L'UID doit être prévisible pour pouvoir être écrasé par un nouvel upload de fichier ICS si modification de certains événements.
              icsContent += `
BEGIN:VEVENT
UID:${yearStr}${monthStr}${dayStr}@UA0
DTSTAMP:${formatDateToICS(now)}
DTSTART:${yearStr}${monthStr}${dayStr}
DTEND:${yearStr}${monthStr}${dayStr}
SUMMARY:${eventSummary}
DESCRIPTION:${eventDescription}
END:VEVENT`
            }
          }
        })
      }
    })

    icsContent += '\nEND:VCALENDAR'

    // Téléchargement du fichier
    await downloadFile(icsContent, `schedule.ics`, 'text/calendar')
  } catch (error) {
    console.error('Erreur lors de la génération du fichier ICS:', error)
    alert(`Impossible de générer le calendrier : ${error.message}`)
  }
}

// Fonction générique pour télécharger un fichier
async function downloadFile(content, fileName, mimeType = 'application/octet-stream') {
  try {
    const blob = new Blob([content], { type: mimeType })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = fileName
    link.click()
    URL.revokeObjectURL(url)
  } catch (error) {
    console.error('Erreur lors du téléchargement:', error)
    alert('Impossible de télécharger le fichier')
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const generateButton = document.getElementById('generate-ics')
  if (generateButton) {
    generateButton.addEventListener('click', generateIcsFile)
  } else {
    console.warn('Bouton de génération ICS non trouvé')
  }
})
