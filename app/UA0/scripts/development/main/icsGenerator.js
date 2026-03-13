/**
 * @file icsGenerator.js
 * @version 2.6
 * @description Version "Mobile-First" : Suppression BOM, limitation 1 an, et nettoyage RFC 5545.
 */

const ICS_CONFIG = Object.freeze({
  MAX_FUTURE_YEARS: 1, // Réduit à 1 an pour performance mobile
  PRODUCT_ID: '-//ScripturaUA0//ICS Generator v1.0//FR',
  STORAGE_KEY: 'scheduleData',
  
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
  toEpochDay: (date) => Math.floor(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000),
  toIcsDay: (date) => date.getFullYear() + String(date.getMonth() + 1).padStart(2, '0') + String(date.getDate()).padStart(2, '0'),
  toIcsTimestamp: (date) => date.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z'
};

function buildEvent(date, summary, description, timestamp) {
  const start = TimeUtils.toIcsDay(date);
  const next = new Date(date);
  next.setDate(next.getDate() + 1);
  const end = TimeUtils.toIcsDay(next);

  // Échappement minimaliste pour éviter les caractères de contrôle
  const cleanSummary = summary.replace(/[,;]/g, '\\$&');
  const cleanDesc = description.replace(/[,;]/g, '\\$&');

  return [
    'BEGIN:VEVENT',
    `UID:${start}@UA0`,
    `DTSTAMP:${timestamp}`,
    `SEQUENCE:0`,
    `STATUS:CONFIRMED`,
    `TRANSP:TRANSPARENT`, // Pour ne pas bloquer le calendrier (disponible)
    `DTSTART;VALUE=DATE:${start}`,
    `DTEND;VALUE=DATE:${end}`,
    `SUMMARY:${cleanSummary}`,
    `DESCRIPTION:${cleanDesc}`,
    'END:VEVENT'
  ].join('\r\n');
}

async function generateIcsFile() {
  const buffer = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    `PRODID:${ICS_CONFIG.PRODUCT_ID}`,
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:Mon Planning'
  ];

  try {
    const rotationOriginStr = localStorage.getItem('startDate');
    if (!rotationOriginStr) throw new Error('Date de début de rotation manquante.');
    
    const rotationOrigin = new Date(rotationOriginStr);
    const originEpoch = TimeUtils.toEpochDay(rotationOrigin);

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

    if (!activePattern || activePattern.length === 0) throw new Error('Pattern introuvable.');

    const scheduleData = JSON.parse(localStorage.getItem(ICS_CONFIG.STORAGE_KEY) || '{}');
    const now = new Date();
    const timestamp = TimeUtils.toIcsTimestamp(now);
    
    let cursor = new Date(now);
    cursor.setHours(0, 0, 0, 0);

    const stopDate = new Date(now);
    stopDate.setFullYear(stopDate.getFullYear() + ICS_CONFIG.MAX_FUTURE_YEARS);

    while (cursor <= stopDate) {
      const year = cursor.getFullYear();
      const month = cursor.getMonth() + 1;
      const day = cursor.getDate();
      
      const currentEpoch = TimeUtils.toEpochDay(cursor);
      const delta = currentEpoch - originEpoch;
      const pLen = activePattern.length;
      const pIdx = ((delta % pLen) + pLen) % pLen;
      const theoreticalCode = activePattern[pIdx];

      const monthKey = `${year}-${month}`;
      const dayData = scheduleData[monthKey]?.[day];
      
      const manualCode = Array.isArray(dayData) ? (dayData[1] || dayData[0]) : dayData;
      const eventCode = manualCode || theoreticalCode;
      
      if (eventCode) {
        const meta = ICS_CONFIG.MAPPING[eventCode] || ICS_CONFIG.DEFAULT_META;
        const baseMeta = ICS_CONFIG.MAPPING[theoreticalCode] || ICS_CONFIG.DEFAULT_META;

        const finalSummary = (theoreticalCode === eventCode || !theoreticalCode)
          ? meta.s
          : `${meta.s} (${baseMeta.s})`;

        buffer.push(buildEvent(cursor, finalSummary, meta.d, timestamp));
      }
      cursor.setDate(cursor.getDate() + 1);
    }

    buffer.push('END:VCALENDAR');
    
    // Jointure finale avec saut de ligne RFC et SANS BOM au début
    const content = buffer.join('\r\n') + '\r\n';
    downloadFile(content, 'planning.ics', 'text/calendar;charset=utf-8');

  } catch (error) {
    console.error('[ICS ERROR]:', error.message);
    alert(`Erreur : ${error.message}`);
  }
}

function downloadFile(content, fileName, mimeType) {
  // Suppression du '\ufeff' (BOM) pour une meilleure compatibilité Android
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 500);
}

document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('generate-ics')?.addEventListener('click', generateIcsFile);
});
