async function generateIcsFile() {
  const scheduleData = JSON.parse(localStorage.getItem('scheduleData')) || {}
  const now = new Date()
  const maxDate = new Date(now)
  maxDate.setFullYear(maxDate.getFullYear() + 1)

  const currentYear = now.getFullYear()
  const currentMonth = now.getMonth() + 1

  // Dictionnaire pour les descriptions des postes
  const descriptions = {
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
    X: '',
    Y: '',
    Z: '',
  }
  const defaultDescription = 'Poste inconnu'

  // Dictionnaire pour les résumés des postes
  const summaries = {
    M: 'M',
    S: 'S',
    J: 'J',
    N: 'N',
    H: 'H sup',
    R: 'R',
    T: 'RTT',
    F: 'RF',
    C: 'CA',
    I: 'Formation',
    A: 'Maladie',
    G: 'Grève',
    D: 'D',
    X: 'X',
    Y: 'Y',
    Z: 'Z',
  }
  const defaultSummary = ''

  let icsContent = `BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//ScripturaUA0//ICS Generator v1.0//FR
`

  // Tri des années et des mois dans les données
  const sortedKeys = Object.keys(scheduleData).sort()

  sortedKeys.forEach(monthKey => {
    const [year, month] = monthKey.split('-').map(Number)

    // Vérifiez si l'année et le mois sont pertinents
    if (year > currentYear || (year === currentYear && month >= currentMonth)) {
      const days = scheduleData[monthKey]
      Object.entries(days).forEach(([day, shifts]) => {
        const eventDate = new Date(year, month - 1, parseInt(day))
        // Inclure uniquement les dates dans la fenêtre autorisée
        if (eventDate >= now && eventDate <= maxDate) {
          const eventName = shifts[1] // Priorité à la deuxième lettre
          if (eventName) {
            const eventSummary = summaries[eventName] || defaultSummary
            const eventDescription = descriptions[eventName] || defaultDescription
            const yearStr = eventDate.getFullYear()
            const monthStr = (eventDate.getMonth() + 1).toString().padStart(2, '0')
            const dayStr = eventDate.getDate().toString().padStart(2, '0')

            // @note L'UID doit être prévisible pour pouvoir être écrasé par un nouvel upload de fichier ICS si modification de l'événement.
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
}

// Fonction pour formater une date en format ICS
function formatDateToICS(date) {
  return date.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z'
}

// Fonction générique pour télécharger un fichier
async function downloadFile(content, fileName, mimeType = 'application/octet-stream') {
  const blob = new Blob([content], { type: mimeType })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = fileName
  link.click()
  URL.revokeObjectURL(url)
}

document.getElementById('generate-ics').addEventListener('click', generateIcsFile)
