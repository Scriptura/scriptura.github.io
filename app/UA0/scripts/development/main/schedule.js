// prettier-ignore
const RotationPatterns = {
  IDE: [
    'J', 'J', 'S', 'J', 'J', 'R', 'R',
    'S', 'S', 'J', 'M', 'F', 'R', 'R',
    'S', 'J', 'M', 'M', 'R', 'S', 'S',
    'J', 'M', 'R', 'R', 'T', 'M', 'M',
    'M', 'R', 'J', 'S', 'S', 'R', 'R',
    'J', 'J', 'S', 'J', 'M', 'R', 'R',
    'S', 'S', 'J', 'J', 'M', 'R', 'R',
    'F', 'S', 'S', 'J', 'J', 'R', 'R',
    'M', 'M', 'M', 'R', 'S', 'S', 'S',
    'T', 'R', 'R', 'S', 'J', 'M', 'M',
    'R', 'J', 'J', 'S', 'S', 'R', 'R',
  ],
  NightIDE: [
    'N', 'N', 'R', 'R', 'N', 'N', 'N',
    'R', 'R', 'N', 'N', 'R', 'R', 'R',
  ],
  ASH: [
    'M', 'M', 'M', 'M', 'R', 'S', 'S',
    'S', 'S', 'R', 'R', 'M', 'M', 'M',
    'M', 'R', 'S', 'S', 'S', 'R', 'R',
    'T', 'M', 'M', 'M', 'M', 'R', 'R',
  ],
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. REGISTRY — Source de vérité unique des types de journée
//
//    Remplace intégralement :
//      - ScheduleClassManager (classMap + validClasses)
//      - validChars[]  dans CustomPatternManager.validate
//      - validLetters[] dans EditManager.handleCellBlur
//
//    isPattern : autorisé dans un pattern de rotation
//    isManual  : autorisé comme override manuel d'une cellule
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @typedef {{ cssClass: string, isPattern: boolean, isManual: boolean }} DayTypeEntry
 */

/** @type {Map<string, DayTypeEntry>} */
const DayTypeRegistry = new Map([
  ['J', { cssClass: 'event-day',        isPattern: true,  isManual: true }],
  ['S', { cssClass: 'event-evening',    isPattern: true,  isManual: true }],
  ['M', { cssClass: 'event-morning',    isPattern: true,  isManual: true }],
  ['R', { cssClass: 'event-rest',       isPattern: true,  isManual: true }],
  ['T', { cssClass: 'event-extra-rest', isPattern: true,  isManual: true }],
  ['F', { cssClass: 'event-holiday',    isPattern: true,  isManual: true }],
  ['N', { cssClass: 'event-night',      isPattern: true,  isManual: true }],
  ['C', { cssClass: 'event-leave',      isPattern: false, isManual: true }],
  ['I', { cssClass: 'event-formation',  isPattern: false, isManual: true }],
  ['H', { cssClass: 'event-overtime',   isPattern: false, isManual: true }],
  ['A', { cssClass: 'event-stop',       isPattern: false, isManual: true }],
  ['G', { cssClass: 'event-strike',     isPattern: false, isManual: true }],
  ['D', { cssClass: 'event-union',      isPattern: false, isManual: true }],
  ['E', { cssClass: 'event-extra-rest', isPattern: false, isManual: true }],
  .../** @type {[string, DayTypeEntry][]} */ (
    ['L', 'O', 'P', 'Q', 'U', 'V', 'W', 'X', 'Y', 'Z'].map(k => [k, { cssClass: 'event-other', isPattern: false, isManual: true }])
  ),
])

// ═══════════════════════════════════════════════════════════════════════════
// 2. LOGIQUE DE TEMPS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Plage d'affichage : semestre précédent → 4 semestres après le courant.
 * @returns {{ startDate: Date, endDate: Date }}
 */
function getSemesterRange() {
  const today = new Date()
  const currentYear = today.getFullYear()
  const currentSemesterStartMonth = today.getMonth() < 6 ? 0 : 6

  const startYear  = currentSemesterStartMonth === 0 ? currentYear - 1 : currentYear
  const startMonth = currentSemesterStartMonth === 0 ? 6 : 0
  const endYear    = currentYear + 2
  const endMonth   = currentSemesterStartMonth === 0 ? 6 : 12

  return {
    startDate: new Date(startYear, startMonth, 1),
    endDate:   new Date(endYear, endMonth, 0),
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3. BUFFER DE ROTATION AOT
//
//    Pré-calcule les indices de pattern pour toute la plage d'affichage
//    (~900 jours → Uint8Array de 900 octets).
//    Élimine le recalcul modulo à chaque itération de rendu (O(1) par cellule).
// ═══════════════════════════════════════════════════════════════════════════

const RotationBuffer = {
  /** @type {Uint8Array} */
  _indices: new Uint8Array(0),
  /** @type {number} Jour d'époque UTC du premier jour de la plage */
  _epochDay0: 0,

  /**
   * Normalise une Date locale en jour d'époque UTC.
   * Utilise les composantes calendaires (y/m/d) pour éliminer tout décalage DST.
   * Cette fonction est la seule voie de conversion Date → époque dans ce module.
   *
   * Invariant : _toEpochDay et indexFor doivent utiliser exactement cette logique.
   *
   * @param {Date} date
   * @returns {number} Nombre de jours depuis l'époque Unix (UTC midnight)
   */
  _toEpochDay(date) {
    return Math.floor(
      Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86_400_000
    )
  },

  /**
   * Construction AOT. O(N) — appelé une seule fois par génération.
   * @param {Date}     rangeStart
   * @param {Date}     rangeEnd
   * @param {Date}     rotationOrigin  Point zéro du pattern (= startDate − 1 jour)
   * @param {string[]} pattern
   */
  build(rangeStart, rangeEnd, rotationOrigin, pattern) {
    const d0     = this._toEpochDay(rangeStart)
    const dN     = this._toEpochDay(rangeEnd)
    const origin = this._toEpochDay(rotationOrigin)
    const pLen   = pattern.length

    this._epochDay0 = d0
    this._indices   = new Uint8Array(dN - d0 + 1)

    for (let i = 0, len = this._indices.length; i < len; i++) {
      const delta      = d0 + i - origin
      this._indices[i] = ((delta % pLen) + pLen) % pLen
    }
  },

  /**
   * Lookup O(1). Utilise _toEpochDay pour garantir la cohérence avec build().
   * @param {Date} date
   * @returns {number} Indice dans le pattern
   */
  indexFor(date) {
    const slot = this._toEpochDay(date) - this._epochDay0
    return this._indices[slot] ?? 0
  },
}

// ═══════════════════════════════════════════════════════════════════════════
// 4. PATTERN PERSONNALISÉ
// ═══════════════════════════════════════════════════════════════════════════

const CustomPatternManager = {
  /** @type {string[]} */
  pattern: [],

  /** Groupe par semaines de 7 pour l'affichage textarea. */
  formatForDisplay(pattern) {
    const elements = (Array.isArray(pattern) ? pattern.join(',') : pattern)
      .split(',')
      .map(el => el.trim())
      .filter(Boolean)
    const weeks = []
    for (let i = 0; i < elements.length; i += 7) {
      weeks.push(elements.slice(i, i + 7).join(', '))
    }
    return weeks.join(',\n')
  },

  cleanInput(input) {
    return input
      .toUpperCase()
      .replace(/[\s\n\r\t]/g, '')
      .replace(/,+/g, ',')
      .replace(/^,|,$/g, '')
  },

  /**
   * Valide via DayTypeRegistry.isPattern — source unique.
   * @param {string} pattern  Chaîne nettoyée séparée par des virgules
   * @returns {boolean}
   */
  validate(pattern) {
    if (!pattern.trim()) return true
    const patternChars = [...DayTypeRegistry.entries()]
      .filter(([, v]) => v.isPattern)
      .map(([k]) => k)
    for (const char of pattern.split(',').map(c => c.trim()).filter(Boolean)) {
      if (!DayTypeRegistry.get(char)?.isPattern) {
        alert(`Caractère invalide : "${char}"\nAutorisés : ${patternChars.join(', ')}`)
        return false
      }
    }
    return true
  },

  stringToPattern(str) {
    return !str.trim() ? [] : this.cleanInput(str).split(',')
  },

  load() {
    try {
      const saved = localStorage.getItem('rotation-custom-pattern')
      if (saved) this.pattern = JSON.parse(saved)
    } catch {
      this.pattern = []
    }
    return this.pattern.length > 0 ? this.pattern : RotationPatterns.IDE
  },

  save(pattern) {
    this.pattern = pattern
    localStorage.setItem('rotation-custom-pattern', JSON.stringify(pattern))
  },
}

// ═══════════════════════════════════════════════════════════════════════════
// 5. ÉTAT (StorageManager) — Source de vérité unique
//
//    scheduleData : Record<monthId, Record<day, [original, current]>>
//
//    Invariant : le DOM est une projection en lecture seule de cet état.
//    Aucune méthode de cette couche ne lit le DOM.
// ═══════════════════════════════════════════════════════════════════════════

const StorageManager = {
  /**
   * @type {Record<string, Record<string, [string, string]>>}
   * monthId = "YYYY-M"  (mois non zero-padded)
   * day     = numéro du jour (clé string issue de JSON)
   */
  scheduleData: {},

  /**
   * Cache de références DOM vers les cellules td.
   * Clé : `"${monthId}:${day}"` — ex. "2025-3:15"
   * Peuplé par CalendarManager._buildMonthTable, vidé par generateSchedule.
   * Élimine tout querySelector dans render() → lookup O(1) garanti.
   * @type {Map<string, HTMLTableCellElement>}
   */
  _cellCache: new Map(),

  /** Charge scheduleData depuis localStorage. */
  async init() {
    try {
      const raw = localStorage.getItem('scheduleData')
      this.scheduleData = raw ? JSON.parse(raw) : {}
    } catch {
      this.scheduleData = {}
    }
  },

  /**
   * Reconstruit scheduleData depuis le buffer de rotation AOT.
   * Préserve les overrides manuels sur les mois existants.
   * O(N jours dans la plage) — appelé une fois par génération.
   *
   * @param {string[]} pattern
   * @param {Date}     rotationOrigin
   * @param {{ force?: boolean }} [options]
   *   force=true : régénère tous les mois (appel depuis le bouton "Générer")
   *   force=false (défaut) : ne peuple que les mois manquants (restauration init)
   */
  rebuild(pattern, rotationOrigin, { force = false } = {}) {
    if (force) this.scheduleData = {}

    const { startDate: rangeStart, endDate: rangeEnd } = getSemesterRange()
    RotationBuffer.build(rangeStart, rangeEnd, rotationOrigin, pattern)

    // Construire l'ensemble des mois valides dans la plage
    const validMonthSet = new Set()
    const cursor = new Date(rangeStart)
    while (cursor <= rangeEnd) {
      validMonthSet.add(`${cursor.getFullYear()}-${cursor.getMonth() + 1}`)
      cursor.setMonth(cursor.getMonth() + 1)
    }

    // Purger les mois obsolètes
    for (const key of Object.keys(this.scheduleData)) {
      if (!validMonthSet.has(key)) delete this.scheduleData[key]
    }

    // Peupler les mois absents depuis le buffer AOT
    for (const monthId of validMonthSet) {
      if (this.scheduleData[monthId]) continue // Préservation des overrides

      const [year, month] = monthId.split('-').map(Number)
      const daysInMonth   = new Date(year, month, 0).getDate()
      this.scheduleData[monthId] = {}

      for (let day = 1; day <= daysInMonth; day++) {
        const date   = new Date(year, month - 1, day)
        const idx    = RotationBuffer.indexFor(date)
        const letter = pattern[idx] ?? 'J'
        this.scheduleData[monthId][day] = [letter, letter]
      }
    }

    this.persist()
  },

  /**
   * Met à jour une cellule en mémoire. O(1). Aucun accès DOM.
   * @param {string}        monthId
   * @param {string|number} day
   * @param {string}        newValue
   */
  updateCell(monthId, day, newValue) {
    const entry = this.scheduleData[monthId]?.[day]
    if (!entry) return
    const [original] = entry
    this.scheduleData[monthId][day] = newValue === original
      ? [original, original]
      : [original, newValue]
    this.persist()
  },

  /**
   * Persiste l'état mémoire dans localStorage. O(1) — aucun accès DOM.
   */
  persist() {
    try {
      localStorage.setItem('scheduleData', JSON.stringify(this.scheduleData))
    } catch (e) {
      console.error('Erreur de persistance :', e)
    }
  },

  /**
   * Projette scheduleData sur le DOM via _cellCache (O(1) par cellule, zéro querySelector).
   * Préserve les classes structurelles : sunday, current-day, public-holiday.
   * Précondition : _cellCache doit être peuplé (CalendarManager.generateSchedule).
   */
  render() {
    requestAnimationFrame(() => {
      for (const [monthId, monthData] of Object.entries(this.scheduleData)) {
        for (const [day, [original, current]] of Object.entries(monthData)) {
          const cell = this._cellCache.get(`${monthId}:${day}`)
          if (!cell) continue

          const displayValue = current || original

          // Préserver les classes structurelles (assignées à la construction, immuables)
          const isSunday  = cell.classList.contains('sunday')
          const isToday   = cell.classList.contains('current-day')
          const isHoliday = cell.classList.contains('public-holiday')

          cell.className = ''
          if (isSunday)  cell.classList.add('sunday')
          if (isToday)   cell.classList.add('current-day')
          if (isHoliday) cell.classList.add('public-holiday')

          cell.textContent = displayValue
          const entry = DayTypeRegistry.get(displayValue)
          if (entry) cell.classList.add(entry.cssClass)
          if (current !== original) cell.classList.add('modified')
        }
      }
    })
  },
}

// ═══════════════════════════════════════════════════════════════════════════
// 6. RENDU (CalendarManager) — Projection DOM
//
//    Invariant : lit scheduleData, n'écrit jamais scheduleData.
//    La structure de la table est construite sans contenu textuel ;
//    StorageManager.render() applique le contenu en phase 3.
// ═══════════════════════════════════════════════════════════════════════════

const CalendarManager = {
  /**
   * Pipeline de génération en 3 phases :
   *   1. AOT  : RotationBuffer.build  (calcul des indices, O(N) une fois)
   *   2. État : StorageManager.rebuild (peuplement scheduleData)
   *   3. DOM  : construction structure + StorageManager.render (projection)
   *
   * @param {string}   startDateInput  Format YYYY-MM-DD
   * @param {string[]} selectedPattern
   * @param {{ force?: boolean }} [options]
   */
  generateSchedule(startDateInput, selectedPattern, { force = false } = {}) {
    if (!startDateInput) {
      alert('Veuillez entrer une date de début.')
      return
    }

    const rotationOrigin = new Date(startDateInput)
    rotationOrigin.setDate(rotationOrigin.getDate() - 1)

    // Phase 1 & 2 : AOT + mise à jour de l'état
    StorageManager.rebuild(selectedPattern, rotationOrigin, { force })

    // Phase 3a : Réinitialisation du cache DOM (cohérence avec la nouvelle structure)
    StorageManager._cellCache.clear()

    // Phase 3b : Construction de la structure DOM (peuple _cellCache via _buildMonthTable)
    const calendarDiv = document.getElementById('calendar')
    const { startDate: rangeStart, endDate: rangeEnd } = getSemesterRange()
    const fragment = document.createDocumentFragment()

    const cursor = new Date(rangeStart)
    while (cursor <= rangeEnd) {
      this._buildMonthTable(new Date(cursor), fragment)
      cursor.setMonth(cursor.getMonth() + 1)
    }

    calendarDiv.innerHTML = ''
    calendarDiv.appendChild(fragment)

    // Phase 3c : Projection de l'état sur les nœuds DOM via le cache
    StorageManager.render()
  },

  /**
   * Construit la structure d'un mois (table + thead + tbody) sans contenu cellule.
   * Le contenu est appliqué par StorageManager.render().
   * @param {Date}             monthDate
   * @param {DocumentFragment} fragment
   */
  _buildMonthTable(monthDate, fragment) {
    const today      = new Date()
    const tableMonth = monthDate.getMonth()
    const tableYear  = monthDate.getFullYear()

    const monthDiv = document.createElement('div')
    const table    = document.createElement('table')
    table.classList.add('table')
    table.id = `month-${tableMonth + 1}-${tableYear}`
    table.setAttribute('data-month-id', `${tableYear}-${tableMonth + 1}`)

    const isPast = tableYear < today.getFullYear() ||
                   (tableYear === today.getFullYear() && tableMonth < today.getMonth())
    const isCurrent = tableMonth === today.getMonth() && tableYear === today.getFullYear()

    if (isCurrent) {
      table.classList.add('current')
    } else if (isPast) {
      table.classList.add('past')
      monthDiv.classList.add('hidden')
    } else {
      table.classList.add('future')
    }

    // Caption
    const caption = document.createElement('caption')
    caption.textContent = monthDate
      .toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' })
      .replace(/^\p{CWU}/u, c => c.toLocaleUpperCase('fr-FR'))
    table.appendChild(caption)

    // Thead
    const thead     = document.createElement('thead')
    const headerRow = document.createElement('tr')
    for (const label of ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim']) {
      const th = document.createElement('th')
      th.textContent = label
      headerRow.appendChild(th)
    }
    thead.appendChild(headerRow)
    table.appendChild(thead)

    // Tbody
    const monthId      = `${tableYear}-${tableMonth + 1}`
    const tbody        = document.createElement('tbody')
    const firstDay     = new Date(tableYear, tableMonth, 1)
    const daysInMonth  = new Date(tableYear, tableMonth + 1, 0).getDate()
    const firstWd      = (firstDay.getDay() + 6) % 7 // Lundi = 0
    const holidays     = publicHolidays(tableYear)

    const rowsFragment = document.createDocumentFragment()
    let row = document.createElement('tr')
    for (let i = 0; i < firstWd; i++) row.appendChild(document.createElement('td'))

    for (let day = 1; day <= daysInMonth; day++) {
      const date = new Date(tableYear, tableMonth, day)
      const td   = document.createElement('td')
      td.setAttribute('data-day', day)

      if (date.getDay() === 0) td.classList.add('sunday')

      if (day === today.getDate() && tableMonth === today.getMonth() && tableYear === today.getFullYear()) {
        td.classList.add('current-day')
      }

      if (Object.values(holidays).some(d => d.toDateString() === date.toDateString())) {
        td.classList.add('public-holiday')
      }

      // Enregistrement dans le cache : clé "monthId:day" → référence directe au nœud
      StorageManager._cellCache.set(`${monthId}:${day}`, td)

      row.appendChild(td)

      if ((firstWd + day) % 7 === 0) {
        rowsFragment.appendChild(row)
        row = document.createElement('tr')
      }
    }

    if (row.children.length > 0) {
      while (row.children.length < 7) row.appendChild(document.createElement('td'))
      rowsFragment.appendChild(row)
    }

    tbody.appendChild(rowsFragment)
    table.appendChild(tbody)
    monthDiv.appendChild(table)
    fragment.appendChild(monthDiv)
  },
}

// ═══════════════════════════════════════════════════════════════════════════
// 7. ÉDITION
//
//    Cycle Data-First sur blur :
//      Input utilisateur → updateCell O(1) → nœud DOM ciblé → persist
//
//    Aucun scan DOM lors de la sauvegarde.
// ═══════════════════════════════════════════════════════════════════════════

const EditManager = {
  isEditingEnabled: false,
  /** @type {HTMLTableCellElement[]} Cache des cellules éditables */
  _editableCells: [],

  toggleEditing(calendarDiv, editableButton) {
    if (!document.querySelectorAll('table[id^="month-"]').length) {
      alert("Veuillez d'abord générer le planning.")
      return
    }

    this.isEditingEnabled = !this.isEditingEnabled
    const [editText, disableText] = editableButton.querySelectorAll('span')

    if (this.isEditingEnabled) {
      this._editableCells = Array.from(calendarDiv.querySelectorAll('td[data-day]'))
      this._editableCells.forEach(cell => {
        cell.style.cursor = 'pointer'
        cell.setAttribute('tabindex', '0')
        cell.setAttribute('contenteditable', 'true')
      })
      editText.classList.add('hidden')
      disableText.classList.remove('hidden')
      editableButton.classList.add('active')
    } else {
      this._editableCells.forEach(cell => {
        cell.style.cursor = ''
        cell.removeAttribute('tabindex')
        cell.removeAttribute('contenteditable')
      })
      this._editableCells = []
      // scheduleData déjà à jour via updateCell ; persist() = filet de sécurité
      StorageManager.persist()
      editText.classList.remove('hidden')
      disableText.classList.add('hidden')
      editableButton.classList.remove('active')
    }
  },

  toggleHistory(historyButton) {
    if (!document.querySelectorAll('.table.past').length) {
      alert("Veuillez d'abord générer le planning.")
      return
    }
    document.querySelectorAll(':has(>.table.past)').forEach(el => el.classList.toggle('hidden'))
    historyButton.classList.toggle('active')
    historyButton.querySelectorAll('span').forEach(s => s.classList.toggle('hidden'))
  },

  /** @param {MouseEvent} e */
  handleCellClick(e) {
    if (!this.isEditingEnabled) return
    const cell = e.target.closest('td[data-day]')
    if (!cell) return

    cell.focus()
    const range = document.createRange()
    range.selectNodeContents(cell)
    const sel = window.getSelection()
    sel.removeAllRanges()
    sel.addRange(range)
    cell.setAttribute('data-current-value', cell.textContent.trim())
  },

  /** Limite la cellule à 1 caractère en cours de saisie. */
  /** @param {InputEvent} e */
  handleCellInput(e) {
    if (!this.isEditingEnabled) return
    const cell = e.target.closest('td[data-day]')
    if (!cell) return
    const value = cell.textContent.trim().toUpperCase()
    cell.textContent = value.length > 1 ? value.charAt(0) : value
  },

  /**
   * Cycle Data-First :
   *   1. Validation via DayTypeRegistry.isManual (source unique)
   *   2. updateCell O(1) → persist
   *   3. Mise à jour ciblée du nœud DOM (un seul nœud, pas de re-render global)
   * @param {FocusEvent} e
   */
  handleCellBlur(e) {
    if (!this.isEditingEnabled) return
    const cell = e.target.closest('td[data-day]')
    if (!cell) return

    const newValue = cell.textContent.trim().toUpperCase()
    const day      = cell.getAttribute('data-day')
    const monthId  = cell.closest('table')?.getAttribute('data-month-id')
    if (!monthId) return

    const entry = StorageManager.scheduleData[monthId]?.[day]
    if (!entry) return
    const [original, current] = entry

    // Validation : rejeter les valeurs vides ou inconnues du registre
    if (!newValue || !DayTypeRegistry.get(newValue)?.isManual) {
      cell.textContent = current || original
      return
    }

    // 1. Mise à jour état O(1) + persistance (aucun accès DOM)
    StorageManager.updateCell(monthId, day, newValue)

    // 2. Mise à jour ciblée du nœud DOM
    cell.textContent = newValue

    // Reconstruire les classes dynamiques sur ce seul nœud
    Array.from(cell.classList).forEach(cls => {
      if (cls.startsWith('event-') || cls === 'modified' || cls === 'modified-spot') {
        cell.classList.remove(cls)
      }
    })

    const dayEntry = DayTypeRegistry.get(newValue)
    if (dayEntry) cell.classList.add(dayEntry.cssClass)

    if (newValue !== original) {
      cell.classList.add('modified')
      cell.classList.add('modified-spot')
    }
  },
}

// ═══════════════════════════════════════════════════════════════════════════
// 8. POINT D'ENTRÉE
// ═══════════════════════════════════════════════════════════════════════════

document.addEventListener('DOMContentLoaded', async () => {
  await StorageManager.init()

  const calendarDiv       = document.getElementById('calendar')
  const editableButton    = document.getElementById('contenteditable')
  const historyButton     = document.getElementById('history')
  const patternSelect     = document.getElementById('pattern-select')
  const startDateInput    = document.getElementById('start-date')
  const customPatternArea = document.getElementById('custom-pattern')
  const saveCustomPattern = document.getElementById('save-custom-pattern')
  const generateButton    = document.getElementById('generate-schedule')
  const resetButton       = document.getElementById('reset')

  /**
   * Résout le pattern actif selon le sélecteur.
   * @param {string} patternType
   * @returns {string[]}
   */
  function resolvePattern(patternType) {
    if (patternType === 'CUSTOM') return CustomPatternManager.load()
    return RotationPatterns[patternType] ?? RotationPatterns.IDE
  }

  /** Lit le pattern depuis le textarea. */
  function getSelectedPattern() {
    return CustomPatternManager.stringToPattern(customPatternArea.value)
  }

  // ── Initialisation (restauration de l'état sauvegardé) ─────────────────
  CustomPatternManager.load()

  const savedPatternType = localStorage.getItem('patternSelect') || 'IDE'
  const savedStartDate   = localStorage.getItem('startDate')

  patternSelect.value     = savedPatternType
  customPatternArea.value = CustomPatternManager.formatForDisplay(resolvePattern(savedPatternType))

  if (savedStartDate) {
    startDateInput.value = savedStartDate
    // force=false : préserve les overrides manuels existants
    CalendarManager.generateSchedule(savedStartDate, getSelectedPattern(), { force: false })
  }

  // ── Événements ─────────────────────────────────────────────────────────
  editableButton?.addEventListener('click', () =>
    EditManager.toggleEditing(calendarDiv, editableButton)
  )

  historyButton?.addEventListener('click', () =>
    EditManager.toggleHistory(historyButton)
  )

  if (calendarDiv) {
    calendarDiv.addEventListener('click', e => EditManager.handleCellClick(e))
    calendarDiv.addEventListener('input', e => EditManager.handleCellInput(e))
    calendarDiv.addEventListener('blur',  e => EditManager.handleCellBlur(e), true)
  }

  patternSelect.addEventListener('change', function () {
    customPatternArea.value = CustomPatternManager.formatForDisplay(resolvePattern(this.value))
    localStorage.setItem('patternSelect', this.value)
  })

  saveCustomPattern.addEventListener('click', () => {
    const cleaned = CustomPatternManager.cleanInput(customPatternArea.value)
    if (CustomPatternManager.validate(cleaned)) {
      customPatternArea.value = CustomPatternManager.formatForDisplay(cleaned)
      CustomPatternManager.save(CustomPatternManager.stringToPattern(cleaned))
    } else {
      const fallback = CustomPatternManager.pattern.length > 0
        ? CustomPatternManager.pattern
        : resolvePattern(patternSelect.value)
      customPatternArea.value = CustomPatternManager.formatForDisplay(fallback)
    }
  })

  startDateInput.addEventListener('blur', function () {
    if (!this.value) return
    const date = new Date(this.value)
    if (isNaN(date.getTime())) {
      alert('Date invalide. Veuillez réessayer.')
      this.value = ''
      return
    }
    if (date.getDay() !== 1) {
      alert('Veuillez sélectionner un lundi.')
      this.value = ''
    } else {
      localStorage.setItem('startDate', this.value)
    }
  })

  generateButton.addEventListener('click', () => {
    // force=true : régénère depuis le pattern courant (écrase les mois existants)
    CalendarManager.generateSchedule(startDateInput.value, getSelectedPattern(), { force: true })
  })

  resetButton?.addEventListener('click', () => {
    if (window.confirm('Êtes-vous sûr de vouloir effacer toutes vos données sauvegardées ? Cette action est irréversible.')) {
      localStorage.clear()
      location.reload()
    }
  })
})
