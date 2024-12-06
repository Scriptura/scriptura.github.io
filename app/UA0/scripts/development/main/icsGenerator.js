function generateIcsFileForNext11Months() {
  const scheduleData = JSON.parse(localStorage.getItem('scheduleData')) || {}
  const now = new Date()
  const currentYear = now.getFullYear()
  const currentMonth = now.getMonth() + 1 // Mois actuel (1-12)
  const currentDay = now.getDate() // Jour actuel

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

  let monthsProcessed = 0

  // Boucle pour parcourir 11 mois à partir du mois actuel
  for (let monthOffset = 0; monthsProcessed < 11; monthOffset++) {
    const targetDate = new Date(currentYear, currentMonth - 1 + monthOffset)
    const targetYear = targetDate.getFullYear()
    const targetMonth = (targetDate.getMonth() + 1).toString().padStart(2, '0')
    const monthKey = `${targetYear}-${targetMonth}`

    if (scheduleData[monthKey]) {
      Object.entries(scheduleData[monthKey]).forEach(([day, shifts]) => {
        const dayNumber = parseInt(day)
        if (monthOffset === 0 && dayNumber < currentDay) return // Ignore les jours passés du mois actuel

        const eventName = shifts[1] // Priorité à la deuxième lettre
        if (eventName) {
          const eventDescription = descriptions[eventName] || defaultDescription
          const eventDate = new Date(targetYear, targetMonth - 1, dayNumber)
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
      monthsProcessed++
    }
  }

  icsContent += '\nEND:VCALENDAR'

  downloadIcsFile(icsContent, `schedule_${currentYear}-${currentMonth}.ics`)
}

// Formate une date en format ICS
function formatDateToICS(date) {
  return date.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z'
}

// Télécharge le fichier ICS
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
