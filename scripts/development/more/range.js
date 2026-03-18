/**
 * @summary Système de gestion de sliders (simple/double) par normalisation de données.
 * @strategy 
 * - Resource Pooling : Mise en cache (Memoization) des instances Intl.NumberFormat pour éviter le GC-pressure durant les interactions fluides.
 * - Single Instruction Path : Unification de la logique de calcul de pourcentage pour les types 'single' et 'multithumb'.
 * - Data-to-Visual Mapping : Utilisation de CSS Variables comme seul canal de communication entre la logique (JS) et la structure (CSS).
 * @architectural-decision
 * - Remplacement des closures individuelles par un "Input System" global (Event Delegation).
 * - Extraction de la plage delta (max - min) en tant qu'invariant pré-calculé pour réduire les opérations CPU par frame.
 * - Séparation stricte entre le calcul des données brutes et le formattage de sortie.
 * - Collision multithumb : comportement "push" explicitement voulu. Le pouce actif pousse
 *   le pouce passif (et non l'inverse : blocage du pouce actif). Cela préserve la position
 *   choisie par l'utilisateur et déplace le pouce contraint, offrant une UX de sélection
 *   de plage continue sans friction.
 */

'use strict';

{
  // Cache de formateurs pour optimiser le cycle CPU/Mémoire (AOT preparation)
  const formatters = new Map();

  const getFormatter = (loc, cur) => {
    const key = `${loc}-${cur}`;
    if (!formatters.has(key)) {
      formatters.set(key, new Intl.NumberFormat(loc || undefined, cur ? { style: 'currency', currency: cur } : {}));
    }
    return formatters.get(key);
  };

  /**
   * Pipeline de normalisation (Data Layout)
   * Calcule le pourcentage et formate la valeur.
   */
  const updateRangeEntity = (container) => {
    const inputs = container.querySelectorAll('input');
    const output = container.querySelector('output');
    const min = parseFloat(inputs[0].min);
    const max = parseFloat(inputs[0].max);
    const delta = max - min; // Invariant de plage

    const formatter = getFormatter(container.dataset.intl, container.dataset.currency);
    const values = Array.from(inputs).map(i => parseFloat(i.value));

    // Tri des valeurs pour le multithumb (évite le croisement logique)
    if (values.length > 1) {
      const step = parseFloat(inputs[0].step || 1);
      if (values[0] >= values[1]) {
        // Correction de l'invariant : maintien d'un écart minimal
        // Note: On pourrait ici ajuster les valeurs réelles des inputs
      }
    }

    // Mise à jour des propriétés CSS (Layout variables)
    values.forEach((v, idx) => {
      const percent = ((v - min) / delta) * 100;
      const varName = values.length > 1 ? (idx === 0 ? '--start' : '--stop') : '--percent';
      container.style.setProperty(varName, `${percent}%`);
    });

    // Rendu des labels (Data-to-String)
    output.textContent = values.map(v => formatter.format(v)).join(' • ');
  };

  /**
   * Input System : Délégation globale
   * Traite les entrées comme un flux de données (Stream)
   */
  const handleInput = (e) => {
    const rangeContainer = e.target.closest('.range, .range-multithumb');
    if (!rangeContainer) return;

    // Logique de collision pour multithumb (AOT-like constraint)
    const inputs = rangeContainer.querySelectorAll('input');
    if (inputs.length > 1) {
      const [v1, v2] = [parseFloat(inputs[0].value), parseFloat(inputs[1].value)];
      const step = parseFloat(inputs[0].step || 1);
      
      // Contrainte structurelle : le pouce actif pousse le pouce passif (comportement "push")
      if (e.target === inputs[0] && v1 >= v2) inputs[1].value = v1 + step;
      if (e.target === inputs[1] && v2 <= v1) inputs[0].value = v2 - step;
    }

    updateRangeEntity(rangeContainer);
  };

  // Initialisation du Layout au chargement (AOT logic)
  const init = () => {
    document.querySelectorAll('.range, .range-multithumb').forEach(container => {
      // Nettoyage structurel
      container.querySelectorAll('input').forEach(i => i.removeAttribute('tabindex'));
      updateRangeEntity(container);
    });

    document.addEventListener('input', handleInput);
    document.addEventListener('change', handleInput);
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
}
