/**
 * @file icsGenerator.js
 * @version 2.5
 * @description Générateur ICS complet avec calcul de rotation déterministe et fusion des overrides.
 */

const ICS_CONFIG = Object.freeze({
  MAX_FUTURE_YEARS: 2, 
  PRODUCT_ID: '-//ScripturaUA0//ICS Generator v1.0//FR',
  STORAGE_KEY: 'scheduleData',
  
  // Mapping des libellés (aligné sur les versions précédentes) 
  MAPPING: {
    M: { s: 'M', d: 'Poste du matin' },
    S: { s: 'S', d: 'Poste du soir' },
    J: { s: 'J', d: 'Poste de journée' },
    N: { s: 'N', d: 'Poste de nuit' },
    H: { s: 'H sup', d: 'Heures supplémentaires' },
    R: { s: 'RH', d: 'Repos' },
    T: { s: 'RT', d: 'Réduction du temps de travail' },
    F: { s: 'RF', d: 'Repos férié' },
    C: { s: 'CA', d: 'Congé annuel' },
    I: { s: 'Formation', d: 'Formation' },
    A: { s: 'Arrêt', d: 'Arrêt de travail ou maladie' },
    G: { s: 'Grève', d: 'Grève' },
    D: { s: 'DS', d: 'Décharge syndicale' },
    E: { s: 'ASA', d: "Autorisation Spéciale d'Absence" },
    X: { s: 'X', d: 'Événement à personnaliser' },
    Y: { s: 'Y', d: 'Événement à personnaliser' },
    Z: { s: 'Z', d: 'Événement à personnaliser' }
  },
  DEFAULT_META: { s: '?', d: 'Événement inconnu' }
});

const TimeUtils = {
  // Calcul du jour de l'époque pour alignement AOT
  toEpochDay: (date) => Math.floor(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000),
  // Formatage conforme RFC 5545 
  toIcsDay: (date) => date.getFullYear() + String(date.getMonth() + 1).padStart(2, '0') + String(date.getDate()).padStart(2, '0'),
  toIcsTimestamp: (date) => date.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z'
};

/**
 * Construit un bloc VEVENT avec UID déterministe (alignement historique) [cite: 2]
 */
function buildEvent(date, summary, description, timestamp) {
  const start = TimeUtils.toIcsDay(date);
  const next = new Date(date);
  next.setDate(next.getDate() + 1);
  const end = TimeUtils.toIcsDay(next);

  return [
    'BEGIN:VEVENT',
    `UID:${start}@UA0`, // Clé primaire persistante pour éviter les doublons
    `DTSTAMP:${timestamp}`,
    `DTSTART;VALUE=DATE:${start}`,
    `DTEND;VALUE=DATE:${end}`,
    `SUMMARY:${summary.replace(/[,;]/g, '\\$&')}`,
    `DESCRIPTION:${description.replace(/[,;]/g, '\\$&')}`,
    'END:VEVENT'
  ].join('\r\n');
}

/**
 * Pipeline principal de génération
 */
async function generateIcsFile() {
  const buffer = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    `PRODID:${ICS_CONFIG.PRODUCT_ID}`,
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:Mon Planning',
    'X-WR-TIMEZONE:Europe/Paris'
  ];

  try {
    // 1. Récupération des paramètres de rotation du localStorage
    const rotationOriginStr = localStorage.getItem('startDate');
    if (!rotationOriginStr) throw new Error('Date de début de rotation (lundi) manquante.');
    
    const rotationOrigin = new Date(rotationOriginStr);
    const originEpoch = TimeUtils.toEpochDay(rotationOrigin);

    // 2. Résolution du pattern actif via l'objet window
    const patternType = localStorage.getItem('patternSelect') || 'IDE';
    let activePattern = [];

    if (patternType === 'CUSTOM') {
      const saved = localStorage.getItem('rotation-custom-pattern');
      activePattern = saved ? JSON.parse(saved) : [];
    } else {
      const registry = window.RotationPatterns;
      if (registry && registry[patternType]) {
        activePattern = registry[patternType];
      }
    }

    if (!activePattern || activePattern.length === 0) {
      throw new Error(`Pattern "${patternType}" introuvable dans window.RotationPatterns.`);
    }

    // 3. Chargement des modifications manuelles (overrides)
    const scheduleData = JSON.parse(localStorage.getItem(ICS_CONFIG.STORAGE_KEY) || '{}');

    const now = new Date();
    const timestamp = TimeUtils.toIcsTimestamp(now);
    
    let cursor = new Date(now);
    cursor.setHours(0, 0, 0, 0);

    const stopDate = new Date(now);
    stopDate.setFullYear(stopDate.getFullYear() + ICS_CONFIG.MAX_FUTURE_YEARS);

    let eventCount = 0;

    // 4. Itération sur la plage temporelle
    while (cursor <= stopDate) {
      const year = cursor.getFullYear();
      const month = cursor.getMonth() + 1;
      const day = cursor.getDate();
      
      // Calcul de la valeur théorique (Rotation Pattern)
      const currentEpoch = TimeUtils.toEpochDay(cursor);
      const delta = currentEpoch - originEpoch;
      const pLen = activePattern.length;
      const pIdx = ((delta % pLen) + pLen) % pLen;
      const theoreticalCode = activePattern[pIdx];

      // Vérification des overrides dans scheduleData 
      const monthKey = `${year}-${month}`;
      const dayData = scheduleData[monthKey]?.[day];
      
      // Si dayData est un tableau [Base, Modif], on prend l'index 1, sinon on prend la valeur simple
      const manualCode = Array.isArray(dayData) ? (dayData[1] || dayData[0]) : dayData;
      const eventCode = manualCode || theoreticalCode;
      
      if (eventCode) {
        const meta = ICS_CONFIG.MAPPING[eventCode] || ICS_CONFIG.DEFAULT_META;
        const baseMeta = ICS_CONFIG.MAPPING[theoreticalCode] || ICS_CONFIG.DEFAULT_META;

        // Composition du titre (ex: "S (M)") si modification 
        const finalSummary = (theoreticalCode === eventCode || !theoreticalCode)
          ? meta.s
          : `${meta.s} (${baseMeta.s})`;

        buffer.push(buildEvent(cursor, finalSummary, meta.d, timestamp));
        eventCount++;
      }

      cursor.setDate(cursor.getDate() + 1);
    }

    buffer.push('END:VCALENDAR');
    
    // Export final avec CRLF et BOM UTF-8 pour Windows/Google Calendar
    const content = buffer.join('\r\n') + '\r\n';
    downloadFile(content, 'schedule.ics', 'text/calendar;charset=utf-8');
    console.log(`[ICS] Export réussi : ${eventCount} événements.`);

  } catch (error) {
    console.error('[ICS ERROR]:', error.message);
    alert(`Erreur de génération : ${error.message}`);
  }
}

/**
 * Téléchargement du Blob avec BOM UTF-8
 */
function downloadFile(content, fileName, mimeType) {
  const blob = new Blob(['\ufeff', content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 500);
}

// Initialisation au chargement du DOM
document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('generate-ics')?.addEventListener('click', generateIcsFile);
});
