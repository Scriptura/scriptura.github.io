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
    E: 'Autorisation Spéciale d\'Absence',
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
    T: 'RT',
    F: 'RF',
    C: 'CA',
    I: 'Formation',
    A: 'Arrêt',
    G: 'Grève',
    D: 'DS',
    E: 'ASA',
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

// Fonction de génération du contenu de l'événement ICS
function generateEventContent(yearStr, monthStr, dayStr, eventSummary, eventDescription, now) {
  // Calcul de la date de fin (le jour suivant)
  const endDate = new Date(`${yearStr}-${monthStr}-${dayStr}`)
  endDate.setDate(endDate.getDate() + 1)

  const endYearStr = endDate.getFullYear().toString()
  const endMonthStr = (endDate.getMonth() + 1).toString().padStart(2, '0')
  const endDayStr = endDate.getDate().toString().padStart(2, '0')

  return `
BEGIN:VEVENT
UID:${yearStr}${monthStr}${dayStr}@UA0
DTSTAMP:${formatDateToICS(now)}
DTSTART;VALUE=DATE:${yearStr}${monthStr}${dayStr}
DTEND;VALUE=DATE:${endYearStr}${endMonthStr}${endDayStr}
SUMMARY:${eventSummary}
DESCRIPTION:${eventDescription}
END:VEVENT`
}

// Génération et téléchargement du fichier ICS
async function generateIcsFile() {
  try {
    // Récupération des données
    const scheduleDataRaw = localStorage.getItem(ICS_CONFIG.STORAGE_KEY)
    const scheduleData = scheduleDataRaw ? JSON.parse(scheduleDataRaw) : {}

    // Préparation des dates
    const now = new Date()
    const startDate = new Date(now)
    startDate.setDate(startDate.getDate() + 1) // Commence à partir de demain
    const maxDate = new Date(now)
    maxDate.setFullYear(maxDate.getFullYear() + ICS_CONFIG.MAX_FUTURE_YEARS)

    // Génération du contenu ICS
    let icsContent = `BEGIN:VCALENDAR
VERSION:2.0
PRODID:${ICS_CONFIG.PRODUCT_ID}
`

    // Génération des événements pour chaque jour
    for (let date = new Date(startDate); date <= maxDate; date.setDate(date.getDate() + 1)) {
      const yearStr = date.getFullYear().toString()
      const monthStr = (date.getMonth() + 1).toString().padStart(2, '0')
      const dayStr = date.getDate().toString().padStart(2, '0')

      const monthKey = `${yearStr}-${monthStr}`
      const dayData = scheduleData[monthKey]?.[dayStr] || []

      const eventName = dayData[1] || null
      if (eventName) {
        const eventSummary =
          dayData[0] === dayData[1]
            ? ICS_CONFIG.EVENT_SUMMARIES[eventName]
            : `${ICS_CONFIG.EVENT_SUMMARIES[eventName]} (${ICS_CONFIG.EVENT_SUMMARIES[dayData[0]]})`
        const eventDescription = ICS_CONFIG.EVENT_DESCRIPTIONS[eventName] || ICS_CONFIG.DEFAULT_DESCRIPTION

        icsContent += generateEventContent(yearStr, monthStr, dayStr, eventSummary, eventDescription, now)
      }
    }

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
