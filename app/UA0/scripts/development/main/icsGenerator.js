/**
 * @file icsGenerator.js
 * @version 2.6.2
 * @description Correction du trigger de téléchargement : Invariant de User Activation.
 *
 * LIMITATION TECHNIQUE MAJEURE : "Android 200-Event Buffer"
 * -----------------------------------------------------------------------
 * Constat : Sur les environnements Android (Google Calendar Importer), 
 * l'importation de fichiers .ics locaux est tronquée après ~200 événements.
 * * Symptôme : Les données sont correctement générées dans le fichier (vérifié 
 * via ADB/Ubuntu), mais l'application mobile arrête l'ingestion sans erreur 
 * explicite (ex: arrêt systématique au bout de 6-7 mois de planning).
 * * Invariant : Pour garantir la synchronisation des jours de repos (RH/R) 
 * et permettre l'écrasement des anciens cycles, tous les jours restent 
 * inclus explicitement, quitte à subir cette troncature temporelle.
 * * Solution de contournement : Si un horizon > 6 mois est requis sur mobile,
 * réduire MAX_FUTURE_YEARS ou segmenter l'export.
 * -----------------------------------------------------------------------
 */

const ICS_CONFIG = Object.freeze({
  MAX_FUTURE_YEARS: 1,
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

  return [
    'BEGIN:VEVENT',
    `UID:${start}@UA0`,
    `DTSTAMP:${timestamp}`,
    `SEQUENCE:0`,
    `STATUS:CONFIRMED`,
    `TRANSP:TRANSPARENT`,
    `DTSTART;VALUE=DATE:${start}`,
    `DTEND;VALUE=DATE:${end}`,
    `SUMMARY:${summary.replace(/[,;]/g, '\\$&')}`,
    `DESCRIPTION:${description.replace(/[,;]/g, '\\$&')}`,
    'END:VEVENT'
  ].join('\r\n');
}

// Suppression du mot-clé async pour rester dans la tâche synchrone du clic
function generateIcsFile() {
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
      const registry = window.RotationPatterns || {};
      activePattern = registry[patternType] || [];
    }

    if (activePattern.length === 0) throw new Error('Pattern vide.');

    const scheduleData = JSON.parse(localStorage.getItem(ICS_CONFIG.STORAGE_KEY) || '{}');
    const now = new Date();
    const timestamp = TimeUtils.toIcsTimestamp(now);
    
    let cursor = new Date(now);
    cursor.setHours(0, 0, 0, 0);

    const stopDate = new Date(now);
    stopDate.setFullYear(stopDate.getFullYear() + ICS_CONFIG.MAX_FUTURE_YEARS);

    const buffer = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      `PRODID:${ICS_CONFIG.PRODUCT_ID}`,
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:Mon Planning'
    ];

    while (cursor <= stopDate) {
      const year = cursor.getFullYear();
      const month = cursor.getMonth() + 1;
      const day = cursor.getDate();
      
      const currentEpoch = TimeUtils.toEpochDay(cursor);
      const delta = currentEpoch - originEpoch;
      const pIdx = ((delta % activePattern.length) + activePattern.length) % activePattern.length;
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

        buffer.push(buildEvent(new Date(cursor), finalSummary, meta.d, timestamp));
      }
      cursor.setDate(cursor.getDate() + 1);
    }

    buffer.push('END:VCALENDAR');
    const content = buffer.join('\r\n') + '\r\n';
    
    // Pipeline de téléchargement durci pour Android
    const blob = new Blob([content], { type: 'text/calendar;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    
    link.style.display = 'none';
    link.href = url;
    link.download = 'planning.ics';
    
    // Invariant : Le lien doit être dans le DOM pour certains navigateurs mobiles
    document.body.appendChild(link);
    link.click();
    
    // Nettoyage atomique
    setTimeout(() => {
      document.body.removeChild(link);
      URL.revokeObjectURL(url);
    }, 100);

  } catch (error) {
    console.error('[ICS ERROR]:', error);
    alert(`Erreur : ${error.message}`);
  }
}

document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('generate-ics')?.addEventListener('click', generateIcsFile);
});
