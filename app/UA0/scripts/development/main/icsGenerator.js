/**
 * @file icsGenerator.js
 * @version 2.1
 * @description Générateur ICS optimisé : correction DST, gestion de buffer et mapping strict.
 */

const ICS_CONFIG = Object.freeze({
  MAX_FUTURE_YEARS: 1, // Valeur d'origine
  PRODUCT_ID: '-//ScripturaUA0//ICS Generator v1.0//FR',
  STORAGE_KEY: 'scheduleData',
  
  // Mapping fusionné pour un accès O(1) sans indirection inutile
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

/**
 * Formate une date pour les champs DTSTART/DTEND (Format DATE sans heure)
 */
const toIcsDay = (date) => {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}${m}${d}`;
};

/**
 * Formate le timestamp DTSTAMP (ISO 8601 Basic)
 */
const toIcsTimestamp = (date) => date.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z';

/**
 * Factory de VEVENT
 * Note : DTEND est exclusif selon la norme RFC 5545 pour VALUE=DATE.
 */
function buildEvent(date, summary, description, timestamp) {
  const start = toIcsDay(date);
  const next = new Date(date);
  next.setDate(next.getDate() + 1);
  const end = toIcsDay(next);

  return [
    'BEGIN:VEVENT',
    `UID:${start}@UA0`,
    `DTSTAMP:${timestamp}`,
    `DTSTART;VALUE=DATE:${start}`,
    `DTEND;VALUE=DATE:${end}`,
    `SUMMARY:${summary}`,
    `DESCRIPTION:${description}`,
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
    'METHOD:PUBLISH'
  ];

  try {
    const rawData = localStorage.getItem(ICS_CONFIG.STORAGE_KEY);
    if (!rawData) throw new Error('Aucune donnée trouvée dans le stockage local.');
    const scheduleData = JSON.parse(rawData);

    const now = new Date();
    const timestamp = toIcsTimestamp(now);

    // Initialisation du curseur (étalonnage à demain 00:00:00)
    let cursor = new Date(now);
    cursor.setDate(cursor.getDate() + 1);
    cursor.setHours(0, 0, 0, 0);

    // Borne de fin
    const stopDate = new Date(now);
    stopDate.setFullYear(stopDate.getFullYear() + ICS_CONFIG.MAX_FUTURE_YEARS);
    stopDate.setHours(23, 59, 59, 999);

    // Itération par mutation d'état (immunisé contre les dérives DST)
    while (cursor <= stopDate) {
      const y = cursor.getFullYear();
      const m = cursor.getMonth() + 1;
      const d = cursor.getDate();

      const dayKey = d.toString();
      const monthKey = `${y}-${m}`;
      const dayData = scheduleData[monthKey]?.[dayKey];

      // Traitement si donnée présente (longueur > 0)
      if (dayData && dayData.length > 0) {
        const baseCode = dayData[0];
        const eventCode = dayData[1] || baseCode; // Fallback structurel

        const meta = ICS_CONFIG.MAPPING[eventCode] || ICS_CONFIG.DEFAULT_META;
        const baseMeta = ICS_CONFIG.MAPPING[baseCode] || ICS_CONFIG.DEFAULT_META;

        // Logique de composition du Summary
        const finalSummary = (baseCode === eventCode)
          ? meta.s
          : `${meta.s} (${baseMeta.s})`;

        buffer.push(buildEvent(cursor, finalSummary, meta.d, timestamp));
      }

      // Incrément atomique
      cursor.setDate(cursor.getDate() + 1);
    }

    buffer.push('END:VCALENDAR');
    downloadFile(buffer.join('\r\n'), 'schedule.ics', 'text/calendar');

  } catch (error) {
    console.error('[ICS GENERATOR ERROR]:', error.message);
    alert(`Erreur lors de la génération : ${error.message}`);
  }
}

/**
 * Abstraction du téléchargement
 */
function downloadFile(content, fileName, mimeType) {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  
  link.href = url;
  link.download = fileName;
  link.click();
  
  // Cleanup mémoire différé
  setTimeout(() => URL.revokeObjectURL(url), 150);
}

// Entry Point
document.addEventListener('DOMContentLoaded', () => {
  const btn = document.getElementById('generate-ics');
  if (btn) {
    btn.addEventListener('click', generateIcsFile);
  } else {
    console.warn('Bouton #generate-ics absent du DOM.');
  }
});
