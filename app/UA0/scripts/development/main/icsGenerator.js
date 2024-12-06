// Fonction pour récupérer les 12 mois à venir à partir des données "scheduleData"
function generateIcsFileForNextYear() {
  const scheduleData = JSON.parse(localStorage.getItem('scheduleData')) || {}
  const now = new Date()
  const currentYear = now.getFullYear()
  const nextYear = currentYear + 1

  // Dictionnaire pour les descriptions des postes
  const descriptions = {
    M: 'Poste du matin',
    J: 'Poste de journée',
    S: 'Poste du soir',
    R: 'Repos',
    T: 'RTT',
    C: 'Congé',
  }
  const defaultDescription = 'Poste inconnu'

  let icsContent = 'BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//VotreEntreprise//Agenda ICS//FR\n'

  for (let month = 1; month <= 12; month++) {
    const monthKey = `${nextYear}-${month.toString().padStart(2, '0')}`

    if (scheduleData[monthKey]) {
      Object.entries(scheduleData[monthKey]).forEach(([day, shifts]) => {
        const eventName = shifts[1] // Priorité à la deuxième lettre
        if (eventName) {
          const eventDescription = descriptions[eventName] || defaultDescription
          const eventDate = new Date(nextYear, month - 1, parseInt(day))
          const year = eventDate.getFullYear()
          const monthStr = (eventDate.getMonth() + 1).toString().padStart(2, '0')
          const dayStr = eventDate.getDate().toString().padStart(2, '0')

          icsContent += `
BEGIN:VEVENT
UID:event-${year}-${monthStr}-${dayStr}-${eventName}@${window.location.hostname}
DTSTAMP:${formatDateToICS(now)}
DTSTART:${year}${monthStr}${dayStr}
DTEND:${year}${monthStr}${dayStr}
SUMMARY:${eventName}
DESCRIPTION:${eventDescription}
END:VEVENT`
        }
      })
    }
  }

  icsContent += '\nEND:VCALENDAR'

  downloadIcsFile(icsContent, `schedule_${nextYear}.ics`)
}

// Fonction pour formater une date en format ICS
function formatDateToICS(date) {
  return date.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z'
}

// Fonction pour télécharger le fichier ICS
function downloadIcsFile(content, fileName) {
  const blob = new Blob([content], { type: 'text/calendar' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = fileName
  link.click()
  URL.revokeObjectURL(url)
}

document.getElementById('generate-ics').addEventListener('click', generateIcsFileForNextYear)
