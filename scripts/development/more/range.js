/**
 * @summary Système de gestion de sliders (simple/double) par normalisation de données.
 * @strategy
 * - Resource Pooling     : Memoization des instances Intl.NumberFormat (réduction GC-pressure).
 * - Single Instruction   : Pipeline unifié pour les types 'single' et 'multithumb'.
 * - Data-to-Visual       : CSS Variables comme seul canal JS → CSS.
 * - A11y Data Layer      : Mise à jour ARIA dans le même passage pipeline que les CSS vars.
 * @architectural-decision
 * - Event Delegation globale (Input System) : remplace les closures par instance.
 * - `delta` (max − min) pré-calculé comme invariant de plage.
 * - Séparation stricte calcul brut / formatage sortie.
 * - Collision multithumb : comportement "push" — le pouce actif déplace le pouce passif,
 *   avec un écart minimal configurable (`data-min-gap`), jamais inférieur à `step`.
 * @data-attributes
 * - `data-intl`     : locale Intl.NumberFormat (ex. "fr-FR"). Optionnel.
 * - `data-currency` : code devise ISO 4217 (ex. "EUR"). Optionnel.
 * - `data-min-gap`  : écart minimal entre les deux thumbs (multithumb). Défaut : step.
 */

'use strict';

{
  // ─── Utilitaires ────────────────────────────────────────────────────────────

  /**
   * Borne une valeur entre [lo, hi]. Fonction pure, sans effet de bord.
   * Si v n'est pas fini (NaN, ±Infinity), retourne lo — comportement déterministe
   * qui arrête la propagation de NaN dans le pipeline de normalisation.
   */
  const clamp = (v, lo, hi) => isFinite(v) ? Math.min(Math.max(v, lo), hi) : lo;

  // Cache de formateurs (AOT preparation — évite les allocations durant les interactions)
  const formatters = new Map();

  /**
   * Configuration pré-calculée par container (AOT init).
   * WeakMap : pas de pollution DOM, libération automatique si le nœud est retiré du document.
   * Structure : { minGap: number }
   */
  const containerConfig = new WeakMap();

  /**
   * Retourne un Intl.NumberFormat mis en cache pour (locale, currency).
   * @param {string} loc  - Locale BCP 47 (ex. "fr-FR").
   * @param {string} cur  - Code devise ISO 4217 (ex. "EUR"). Optionnel.
   */
  const getFormatter = (loc, cur) => {
    const key = `${loc}-${cur}`;
    if (!formatters.has(key)) {
      formatters.set(
        key,
        new Intl.NumberFormat(
          loc || undefined,
          cur ? { style: 'currency', currency: cur } : {}
        )
      );
    }
    return formatters.get(key);
  };

  // ─── Pipeline de normalisation ───────────────────────────────────────────────

  /**
   * Calcule les pourcentages, met à jour les CSS vars et l'état ARIA.
   * Passage unique sur les valeurs : CSS vars + ARIA dans la même boucle.
   * @param {Element} container - Élément `.range` ou `.range-multithumb`.
   */
  const updateRangeEntity = (container) => {
    const inputs = container.querySelectorAll('input');
    const output = container.querySelector('output');
    const min    = parseFloat(inputs[0].min);
    const max    = parseFloat(inputs[0].max);
    const delta  = max - min;

    // Guard fail-fast : delta nul ou invalide signale une configuration HTML incorrecte
    // (min >= max ou attributs manquants). On arrête le pipeline plutôt que de masquer
    // l'erreur avec un fallback — le warn permet à l'intégrateur de la détecter.
    if (!delta || !isFinite(delta)) {
      console.warn('[range] Configuration invalide : min >= max ou attributs absents.', container);
      return;
    }

    const formatter = getFormatter(container.dataset.intl, container.dataset.currency);
    const isMulti   = inputs.length > 1;
    const values    = Array.from(inputs).map(i => clamp(parseFloat(i.value), min, max));

    // Passage unique : CSS vars + état ARIA (évite une double traversée du tableau)
    values.forEach((v, idx) => {
      const percent = ((v - min) / delta) * 100;
      const varName = isMulti ? (idx === 0 ? '--start' : '--stop') : '--percent';
      container.style.setProperty(varName, `${percent}%`);

      // A11y data layer : synchronisation de l'état sémantique
      const input = inputs[idx];
      input.setAttribute('aria-valuemin',  min);
      input.setAttribute('aria-valuemax',  max);
      input.setAttribute('aria-valuenow',  v);
      input.setAttribute('aria-valuetext', formatter.format(v));
    });

    // Rendu texte de l'output (Data-to-String)
    // Guard : output peut être absent en cas d'intégration partielle du DOM.
    if (output) output.textContent = values.map(v => formatter.format(v)).join(' • ');
  };

  // ─── Input System (Event Delegation globale) ─────────────────────────────────

  /**
   * Traite les événements input/change comme un flux de données.
   * Applique la contrainte de collision avant de relancer le pipeline.
   * @param {Event} e
   */
  const handleInput = (e) => {
    const rangeContainer = e.target.closest('.range, .range-multithumb');
    if (!rangeContainer) return;

    const inputs = rangeContainer.querySelectorAll('input');

    if (inputs.length > 1) {
      const min    = parseFloat(inputs[0].min);
      const max    = parseFloat(inputs[0].max);
      // minGap lu depuis le cache AOT — zéro parsing à chaud.
      // Guard : containerConfig peut être absent si le container a été injecté
      // dynamiquement après init() (ex. SPA). Fallback silencieux sur step.
      const step      = parseFloat(inputs[0].step) || 1;
      const config    = containerConfig.get(rangeContainer);
      const minGap    = config ? config.minGap : step;

      const v1 = parseFloat(inputs[0].value);
      const v2 = parseFloat(inputs[1].value);

      // Comportement "push" : le pouce actif déplace le pouce passif
      if (e.target === inputs[0] && v1 >= v2) {
        inputs[1].value = clamp(v1 + minGap, min, max);
      }
      if (e.target === inputs[1] && v2 <= v1) {
        inputs[0].value = clamp(v2 - minGap, min, max);
      }
    }

    updateRangeEntity(rangeContainer);
  };

  // ─── Initialisation (AOT layout) ─────────────────────────────────────────────

  /**
   * Prépare chaque container : nettoyage structurel, ARIA initial, état CSS.
   * Exécuté une seule fois au chargement.
   */
  const init = () => {
    document.querySelectorAll('.range, .range-multithumb').forEach(container => {
      const inputs = container.querySelectorAll('input');
      const output = container.querySelector('output');
      const isMulti = inputs.length > 1;

      inputs.forEach((input, idx) => {
        // Nettoyage structurel : suppression du tabindex natif redondant
        input.removeAttribute('tabindex');

        // Labels ARIA pour différencier les thumbs (multithumb uniquement)
        // Défini une seule fois ici pour ne pas écraser une valeur HTML explicite
        if (isMulti && !input.hasAttribute('aria-label')) {
          input.setAttribute('aria-label', idx === 0 ? 'Minimum' : 'Maximum');
        }
      });

      // aria-live sur l'output : annonce les changements aux lecteurs d'écran
      // "polite" : attend la fin de la lecture en cours (non interruptif)
      if (output && !output.hasAttribute('aria-live')) {
        output.setAttribute('aria-live', 'polite');
      }

      // Pré-calcul de minGap (AOT) : évite le re-parsing à chaque événement input.
      // Stocké dans containerConfig (WeakMap) — pas de sérialisation dans le DOM.
      if (inputs.length > 1) {
        const step   = parseFloat(inputs[0].step) || 1;
        const minGap = Math.max(Number(container.dataset.minGap) || 0, step);
        containerConfig.set(container, { minGap });
      }

      updateRangeEntity(container);
    });

    document.addEventListener('input',  handleInput);
    document.addEventListener('change', handleInput);
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
}
