/**
 * @summary Système de focus d'image autonome par Object Pooling et délégation d'événements.
 * @strategy 
 * - Object Pooling : Création d'une instance unique détachée du DOM en état de repos (Idle) pour éviter les fuites mémoire.
 * - Strict Data Mapping : Injection des attributs (src, alt) uniquement au moment de l'activation pour garantir la validité HTML5.
 * - Unified Input System : Délégation d'événements globale traitant l'ouverture et la fermeture comme des transitions d'état.
 * @architectural-decision
 * - Le composant est physiquement retiré du DOM (Node.remove()) à la fermeture pour prévenir tout conflit avec la cascade CSS, tout en restant alloué en mémoire.
 * - Suppression des conteneurs intermédiaires : mapping strict sur la classe d'origine `.picture-area` pour respecter le layout pré-existant.
 */
'use strict';

{
  const CONFIG = {
    TRIGGER_SELECTOR: '[class*="-focus"]',
    OVERLAY_ID: 'picture-focus-overlay',
    OVERLAY_CLASS: 'picture-area' // Alignement strict avec votre CSS d'origine
  };

  const state = {
    activeTrigger: null,
    overlay: null,
    imgEntity: null,
    siblings: []
  };

  /**
   * Construction du Prefab en mémoire (AOT)
   */
  const bootstrapSystem = () => {
    if (document.getElementById(CONFIG.OVERLAY_ID)) return;

    const overlay = document.createElement('div');
    overlay.id = CONFIG.OVERLAY_ID;
    overlay.className = CONFIG.OVERLAY_CLASS;

    // Prefab valide : omission stricte des attributs vides
    overlay.innerHTML = `
      <img loading="lazy">
      <button class="shrink-button" aria-label="shrink"></button>
    `;

    state.overlay = overlay;
    state.imgEntity = overlay.querySelector('img');

    const shrinkBtn = overlay.querySelector('.shrink-button');
    if (typeof injectSvgSprite === 'function') {
      injectSvgSprite(shrinkBtn, 'minimize');
    }
  };

  /**
   * System State Machine
   */
  const setSystemState = (target = null) => {
    const isOpening = !!target;
    const root = document.documentElement;

    root.classList.toggle('freeze', isOpening);

    if (isOpening) {
      state.activeTrigger = target;
      const sourceImg = target.querySelector('img');
      
      // Data Injection
      state.imgEntity.setAttribute('src', sourceImg.src);
      if (sourceImg.alt) state.imgEntity.setAttribute('alt', sourceImg.alt);

      // Entity Attachment (Insertion DOM)
      document.body.appendChild(state.overlay);

      // Gestion de l'accessibilité (Calcul O(N) sécurisé après insertion)
      state.siblings = Array.from(document.body.children).filter(el => el !== state.overlay);
      state.siblings.forEach(el => el.setAttribute('inert', ''));
      
      state.overlay.querySelector('button')?.focus();
    } else {
      // Context Restoration
      state.siblings.forEach(el => el.removeAttribute('inert'));
      state.activeTrigger?.querySelector('button')?.focus();
      state.activeTrigger = null;
      
      // Data Flush & Entity Detachment
      state.imgEntity.removeAttribute('src');
      state.imgEntity.removeAttribute('alt');
      state.overlay.remove(); // Retire l'élément visuellement sans le détruire en mémoire
    }
  };

  /**
   * Input Processor
   */
  const handleInteraction = (e) => {
    const trigger = e.target.closest(CONFIG.TRIGGER_SELECTOR);
    if (trigger && !state.activeTrigger) {
      setSystemState(trigger);
      return;
    }

    if (state.activeTrigger) {
      const isOverlayClick = e.target.closest(`#${CONFIG.OVERLAY_ID}`);
      if (isOverlayClick) {
        setSystemState(null);
      }
    }
  };

  const init = () => {
    const targets = document.querySelectorAll(CONFIG.TRIGGER_SELECTOR);
    if (!targets.length) return;

    // AOT : Préparation des déclencheurs
    targets.forEach(item => {
      if (item.querySelector('button')) return;
      const btn = document.createElement('button');
      btn.ariaLabel = 'enlarge';
      if (typeof injectSvgSprite === 'function') injectSvgSprite(btn, 'maximize');
      item.appendChild(btn);
    });

    bootstrapSystem();
    document.addEventListener('click', handleInteraction);
    
    // Support clavier
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && state.activeTrigger) setSystemState(null);
    });
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
}
