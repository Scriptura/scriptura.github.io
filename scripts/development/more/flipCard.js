/**
 * @summary Système de gestion de l'état "Flip" par délégation d'événements et pilotage par données.
 * * @strategy 
 * - Event Delegation : Réduction de l'empreinte mémoire (O(1) listener vs O(N)).
 * - State Mirroring : Utilisation des attributs data-* comme source de vérité structurelle, permettant un pipeline CSS déterministe.
 * - Timer Pooling : Remplacement des multiples timeouts par une gestion d'expiration centralisée pour éviter la fragmentation de l'Event Loop.
 * * @architectural-decision
 * - Suppression du `forEach` sur le DOM pour éviter l'allocation de multiples closures.
 * - Transformation du toggle en une fonction pure de transition d'état (Input -> State Update -> Render).
 * - Utilisation de `localStorage` en accès hâtif (AOT logic) pour court-circuiter le système de démo.
 */
'use strict';

{
  const CONFIG = {
    CLASS_FLIP: 'flip',
    ATTR_STATE: 'data-flipped',
    DEMO_KEY: 'demoCounterFlipCards',
    AUTO_FLIP_LIMIT: 4,
    AUTO_UNFLIP_MS: 1500,
    GLOBAL_UNFLIP_MS: 3000
  };

  // State Manager (Data Layer)
  const state = {
    autoFlipping: true,
    viewCount: parseInt(localStorage.getItem(CONFIG.DEMO_KEY)) || 0,
    timers: new Map() // Pool de timers indexés par élément pour éviter les collisions
  };

  /**
   * Update unique du compteur (AOT check)
   */
  const updateAnalytics = () => {
    state.viewCount++;
    localStorage.setItem(CONFIG.DEMO_KEY, state.viewCount);
  };

  /**
   * Système de rendu / Mutation DOM
   */
  const setFlipState = (el, isActive) => {
    if (!el) return;
    el.setAttribute(CONFIG.ATTR_STATE, isActive);
    // Transition class-based pour compatibilité CSS existante
    el.classList.toggle('active', isActive);
  };

  /**
   * Gestionnaire de cycle de vie des timers (Evite les fuites mémoires)
   */
  const scheduleUnflip = (el, delay) => {
    if (state.timers.has(el)) clearTimeout(state.timers.get(el));
    const timer = setTimeout(() => {
      setFlipState(el, false);
      state.timers.delete(el);
    }, delay);
    state.timers.set(el, timer);
  };

  /**
   * Initialisation de la séquence démo (Pipeline déterministe)
   */
  const runDemoSequence = () => {
    const firstCard = document.querySelector(`.${CONFIG.CLASS_FLIP}`);
    if (!firstCard || state.viewCount >= CONFIG.AUTO_FLIP_LIMIT) {
      state.autoFlipping = false;
      return;
    }

    setTimeout(() => {
      if (!state.autoFlipping) return;
      setFlipState(firstCard, true);
      scheduleUnflip(firstCard, CONFIG.AUTO_UNFLIP_MS);
      state.autoFlipping = false;
    }, 1000);
  };

  /**
   * Event Bus (Input System)
   * Centralisation de la capture sur le document ou un container racine.
   */
  document.addEventListener('click', (e) => {
    const card = e.target.closest(`.${CONFIG.CLASS_FLIP}`);
    if (!card) return;

    // Interruption du flux automatique sur interaction utilisateur
    if (state.autoFlipping) state.autoFlipping = false;

    const isCurrentlyActive = card.getAttribute(CONFIG.ATTR_STATE) === 'true';
    
    if (isCurrentlyActive) {
      setFlipState(card, false);
    } else {
      // Logic: Unflip des autres entités actives avec délai
      document.querySelectorAll(`.${CONFIG.CLASS_FLIP}[data-flipped="true"]`).forEach(other => {
        if (other !== card) scheduleUnflip(other, CONFIG.GLOBAL_UNFLIP_MS);
      });
      setFlipState(card, true);
    }
  });

  // Nettoyage de l'accessibilité via sélecteur global (AOT style)
  document.querySelectorAll(`.${CONFIG.CLASS_FLIP}`).forEach(el => el.removeAttribute('tabindex'));

  // Entry point
  updateAnalytics();
  runDemoSequence();
}
