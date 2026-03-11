// ═══════════════════════════════════════════════════════════════════════════
// STATS.JS — Couche de calcul statistique
//
// Source de vérité : RotationBuffer + StorageManager (schedule.js)
// Invariant : aucun accès direct au localStorage, aucun scraping DOM.
// Toute valeur journalière est résolue via resolveDayValue().
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Résout la valeur finale d'une journée en croisant les deux sources.
 * Miroir exact de la logique de render() dans StorageManager.
 *
 * @param {Date}   date
 * @param {number} year   Année numérique (évite un re-calcul dans les boucles)
 * @param {number} month  Mois 1-indexé
 * @param {number} day    Jour du mois
 * @returns {string} Lettre finale (override manuel ou valeur théorique)
 */
function resolveDayValue(date, year, month, day) {
  const monthId    = `${year}-${month}`
  const theoretical = RotationBuffer._pattern[RotationBuffer.indexFor(date)] ?? 'J'
  const manual      = StorageManager.scheduleData[monthId]?.[day]
  return manual ?? theoretical
}

/**
 * Calcule les occurrences de chaque lettre sur l'année courante.
 * Itère du 1er janvier au 31 décembre — ne lit pas scheduleData en entier.
 *
 * @returns {Record<string, number>}
 */
function calculateLetterStats() {
  const year  = new Date().getFullYear()
  const stats = {}

  for (let month = 1; month <= 12; month++) {
    const daysInMonth = new Date(year, month, 0).getDate()
    for (let day = 1; day <= daysInMonth; day++) {
      const date   = new Date(year, month - 1, day)
      const letter = resolveDayValue(date, year, month, day)
      stats[letter] = (stats[letter] ?? 0) + 1
    }
  }

  return stats
}

/**
 * Calcule le nombre de jours travaillés (M, J, S) tombant un dimanche
 * ou un jour férié sur l'année courante.
 *
 * @returns {number}
 */
function calculateHolidayAndSundayWork() {
  const year     = new Date().getFullYear()
  const holidays = publicHolidays(year)

  // Set de chaînes "YYYY-MM-DD" pour lookup O(1)
  const holidaySet = new Set(
    Object.values(holidays).map(d => {
      // publicHolidays retourne des dates UTC minuit — on extrait la date locale
      const h = new Date(d)
      h.setDate(h.getDate() + 1) // compensation décalage UTC
      return h.toISOString().split('T')[0]
    })
  )

  const workLetters = new Set(['M', 'J', 'S'])
  let count = 0

  for (let month = 1; month <= 12; month++) {
    const daysInMonth = new Date(year, month, 0).getDate()
    for (let day = 1; day <= daysInMonth; day++) {
      const date = new Date(year, month - 1, day)

      if (date.getDay() !== 0) {
        // Pas un dimanche — vérifier jour férié
        const dateStr = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
        if (!holidaySet.has(dateStr)) continue
      }

      // Dimanche ou férié : résoudre et tester
      const letter = resolveDayValue(date, year, month, day)
      if (workLetters.has(letter)) count++
    }
  }

  return count
}

/**
 * Réorganise les statistiques pour intercaler grandes et petites valeurs
 * (améliore la lisibilité du camembert).
 *
 * @param {Record<string, number>} stats
 * @returns {Array<[string, number]>}
 */
function rearrangeStats(stats) {
  const sorted = Object.entries(stats).sort((a, b) => b[1] - a[1])
  const mid    = Math.ceil(sorted.length / 2)
  const high   = sorted.slice(0, mid)
  const low    = sorted.slice(mid)

  const result = []
  for (let i = 0; i < Math.max(high.length, low.length); i++) {
    if (i < high.length) result.push(high[i])
    if (i < low.length)  result.push(low[i])
  }
  return result
}

/**
 * Calcule et injecte les statistiques dans l'élément #stats.
 * Précondition : RotationBuffer._pattern doit être peuplé (generateSchedule appelé).
 */
function updateLetterStats() {
  // Garde-fou : buffer non encore initialisé (page chargée sans date de début)
  if (!RotationBuffer._pattern.length) return

  const stats        = calculateLetterStats()
  const arranged     = rearrangeStats(stats)
  const formattedData = arranged
    .map(([letter, count]) => `{"value": ${count}, "label": "${letter}"}`)
    .join(',')

  const holidayWork = calculateHolidayAndSundayWork()
  const output      = document.getElementById('stats')
  if (!output) return

  output.innerHTML = `
    <pie-chart data='[${formattedData}]' gap="0" donut="0.7"></pie-chart>
    <p>Dimanches et jours fériés travaillés&nbsp;: <strong>${holidayWork}</strong></p>
  `
}

/**
 * Initialise l'observateur de mutations et les listeners.
 * Le MutationObserver cible #calendar pour détecter toute projection DOM
 * issue de StorageManager.render() ou CalendarManager.generateSchedule().
 */
function initializeStats() {
  const debounce = (fn, delay) => {
    let id
    return (...args) => {
      clearTimeout(id)
      id = setTimeout(() => fn(...args), delay)
    }
  }

  const debouncedUpdate = debounce(updateLetterStats, 500)

  const calendarContainer = document.getElementById('calendar')
  if (calendarContainer) {
    new MutationObserver(mutations => {
      const relevant = mutations.some(
        m => m.type === 'childList' ||
             (m.type === 'attributes' && m.target.closest?.('.table'))
      )
      if (relevant) Promise.resolve().then(debouncedUpdate)
    }).observe(calendarContainer, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class'],
    })
  }

  updateLetterStats()

  document.getElementById('generate-schedule')
    ?.addEventListener('click', debouncedUpdate)
}

document.addEventListener('DOMContentLoaded', () => {
  setTimeout(initializeStats, 100)
})
