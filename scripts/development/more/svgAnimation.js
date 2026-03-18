/**
 * @summary Système d'animation de tracés SVG piloté par les données géométriques.
 * @strategy 
 * - AOT Geometry Pre-calculation : Calcul unique des longueurs de tracés à l'initialisation pour éviter les "Layout Thrashing" lors du scroll.
 * - Component Mapping : Stockage des invariants (longueurs, états initiaux) dans une Map centralisée, transformant le handler d'intersection en une opération O(1).
 * - Lifecycle Delegation : Utilisation exclusive de l'IntersectionObserver pour la détection de visibilité, supprimant les calculs manuels de bounding boxes.
 * @architectural-decision
 * - Séparation du "Discovery System" (recherche des SVG) et du "Mutation System" (application des styles).
 * - Utilisation de CSS Variables pour injecter les données calculées (dasharray), déléguant le pipeline d'animation au moteur de rendu du navigateur.
 * - Nettoyage automatique des ressources via `unobserve` et suppression des références dans la Map pour prévenir les fuites mémoire.
 */
'use strict';

{
  // Registre des composants (Data Store)
  const registry = new WeakMap();

  const CONFIG = {
    SELECTOR: 'svg.svg-animation',
    ACTIVE_CLASS: 'active',
    HIDDEN_CLASS: 'invisible-if-animation'
  };

  /**
   * Système de préparation (AOT / Boot phase)
   * Extrait les données géométriques et prépare le DOM.
   */
  const bootstrapSvg = (svg) => {
    const paths = svg.querySelectorAll('path');
    const pathData = Array.from(paths).map(path => {
      const length = path.getTotalLength();
      
      // Injection immédiate des invariants dans le style inline (Data-to-CSS)
      path.style.setProperty('--path-length', length);
      path.setAttribute('stroke-dasharray', length);
      path.setAttribute('stroke-dashoffset', length);

      return {
        ref: path,
        originalDashArray: path.getAttribute('stroke-dasharray'),
        originalDashOffset: path.getAttribute('stroke-dashoffset')
      };
    });

    registry.set(svg, pathData);
  };

  /**
   * Restoration System
   * Réinitialise les attributs après exécution de la logique d'animation.
   */
  const restoreSvg = (svg) => {
    const data = registry.get(svg);
    if (!data) return;

    data.forEach(item => {
      item.originalDashArray 
        ? item.ref.setAttribute('stroke-dasharray', item.originalDashArray) 
        : item.ref.removeAttribute('stroke-dasharray');
      
      item.originalDashOffset 
        ? item.ref.setAttribute('stroke-dashoffset', item.originalDashOffset) 
        : item.ref.removeAttribute('stroke-dashoffset');
    });

    svg.classList.remove(CONFIG.ACTIVE_CLASS);
    registry.delete(svg);
  };

  /**
   * Intersection Handler (Execution System)
   */
  const onIntersection = (entries, observer) => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;

      const svg = entry.target;
      if (svg.classList.contains(CONFIG.ACTIVE_CLASS)) return;

      // Activation
      svg.classList.remove(CONFIG.HIDDEN_CLASS);
      svg.classList.add(CONFIG.ACTIVE_CLASS);

      // Cleanup post-animation
      const onEnd = () => {
        restoreSvg(svg);
        svg.removeEventListener('animationend', onEnd);
        observer.unobserve(svg);
      };

      svg.addEventListener('animationend', onEnd);
    });
  };

  const init = () => {
    // Early exit: User preference check
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    const targets = document.querySelectorAll(CONFIG.SELECTOR);
    if (!targets.length) return;

    const observer = new IntersectionObserver(onIntersection, {
      root: null,
      threshold: 0.5
    });

    targets.forEach(svg => {
      bootstrapSvg(svg);
      observer.observe(svg);
    });
  };

  // Entry point synchronisé avec le cycle de vie du Sprite
  document.addEventListener('svgSpriteInlined', init, { once: true });
}
