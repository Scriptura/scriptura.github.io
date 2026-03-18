/**
 * @summary Moteur d'inlining de sprites SVG par déduplication de ressources et traitement par lots.
 * @strategy
 * - Resource Pooling (Déduplication) : Extraction AOT des URLs uniques pour garantir qu'un fichier SVG n'est téléchargé et parsé qu'une seule fois, indépendamment du nombre de références.
 * - Parallel I/O : Remplacement de l'itération sérielle par des requêtes concurrentes (Promise.all) pour saturer efficacement le réseau.
 * - Batch DOM Mutation : Isolation des manipulations DOM (clonage) via un `DocumentFragment` pour minimiser les invalidations de l'arbre de rendu (Layout Thrashing).
 * @architectural-decision
 * - Séparation stricte entre le sous-système de récupération des données (Data Fetching) et le sous-système d'application visuelle (DOM Mutation).
 * - Utilisation de `replaceChildren()` natif pour purger le SVG parent, plus performant que la boucle `while(firstChild) removeChild`.
 * - Émission garantie de l'événement `svgSpriteInlined` même en cas de sortie prématurée (A11Y) pour prévenir le deadlock des scripts dépendants.
 */
'use strict';

{
  const CONFIG = {
    SELECTOR: '.sprite-to-inline use',
    EVENT_READY: 'svgSpriteInlined'
  };

  // Resource Cache (Data Store) : Associe une URL à un Document SVG parsé en mémoire
  const spriteCache = new Map();

  /**
   * Data Layer : Récupération et parsing concurrents (AOT)
   */
  const loadUniqueSprites = async (urls) => {
    const uniqueUrls = [...new Set(urls)];
    const parser = new DOMParser();

    // Exécution parallèle de toutes les requêtes réseau requises
    await Promise.all(uniqueUrls.map(async (url) => {
      if (spriteCache.has(url)) return;
      
      try {
        const response = await fetch(url);
        const text = await response.text();
        const doc = parser.parseFromString(text, 'image/svg+xml');
        spriteCache.set(url, doc);
      } catch (error) {
        console.error(`Erreur réseau/parsing pour ${url}:`, error);
      }
    }));
  };

  /**
   * Execution Layer : Mutation du DOM
   */
  const mutateEntities = (useElements) => {
    useElements.forEach(useEl => {
      const href = useEl.getAttribute('href');
      if (!href) return;

      const [url, symbolId] = href.split('#');
      const doc = spriteCache.get(url);
      if (!doc) return;

      const symbol = doc.querySelector(`#${symbolId}`);
      if (!symbol) return;

      const parentSvg = useEl.parentElement;
      if (!(parentSvg instanceof SVGSVGElement)) {
        console.error(`L'élément parent n'est pas un SVG.`);
        return;
      }

      // 1. Transfert des invariants (Attributs)
      Array.from(symbol.attributes).forEach(attr => {
        parentSvg.setAttribute(attr.name, attr.value);
      });

      // 2. Construction du nouveau layout en mémoire (Fragment)
      const fragment = document.createDocumentFragment();
      Array.from(symbol.childNodes).forEach(child => {
        // Apprendice direct pour éviter l'injection xmlns non désirée
        fragment.appendChild(child.cloneNode(true)); 
      });

      // 3. Application atomique : Purge rapide et injection
      parentSvg.replaceChildren(fragment);
    });
  };

  /**
   * Main Pipeline
   */
  const executeSystem = async () => {
    // Early exit : Préférences d'accessibilité
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      document.dispatchEvent(new CustomEvent(CONFIG.EVENT_READY));
      return; // Fin du processus, mais le signal de résolution est tout de même émis
    }

    const useElements = Array.from(document.querySelectorAll(CONFIG.SELECTOR));
    if (!useElements.length) {
      document.dispatchEvent(new CustomEvent(CONFIG.EVENT_READY));
      return;
    }

    // AOT : Extraction exclusive des données nécessaires (URLs) avant toute I/O
    const urls = useElements
      .map(el => el.getAttribute('href')?.split('#')[0])
      .filter(Boolean);

    // Pipeline synchrone/asynchrone
    await loadUniqueSprites(urls);
    mutateEntities(useElements);

    // Broadcast de fin de traitement
    document.dispatchEvent(new CustomEvent(CONFIG.EVENT_READY));
  };

  executeSystem();
}
