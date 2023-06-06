class VGrid {
  // En attendant un support masonry natif pour le module CSS Grid layout.
  // @see https://www.smashingmagazine.com/native-css-masonry-layout-css-grid/
  // @credit Vikram Soni @see https://codepen.io/vikramsoni/pen/gOvOKNz
  // @note Le script fait appel à une redistribution des lignes pour la grille
  // @bugfix @affected Chrome @see https://github.com/rachelandrew/gridbugs/issues/28 @note Une limitation à 999 lignes semble avoir été corrigée, nous avons testé avec 600 items sans bugs.

  constructor (container) {
    this.grid = container instanceof HTMLElement ? container : document.querySelector(container) // Initialise la grille et les éléments enfants.
    this.gridItems = [].slice.call(this.grid.children) // Récupère tous les enfants directs.
  }

  resizeGridItem(item) {
    const rowHeight = 1 // précision de la grille, ici la plus grande précision possible.
    const rowGap = parseInt(window.getComputedStyle(this.grid).getPropertyValue('grid-row-gap')) // Récupère les propriétés d'espacement des lignes de la grille, afin que nous puissions l'ajouter aux enfants pour ajouter de l'espace supplémentaire afin d'éviter le débordement de contenu.
    const rowSpan = Math.ceil((item.clientHeight + rowGap) / (rowHeight + rowGap))// clientheight représente la hauteur du conteneur avec le contenu. Nous le divisons par la ligne Height+row Gap pour calculer le nombre de lignes dont il a besoin.
    item.style.gridRowEnd = 'span ' + rowSpan // Définit la propriété CSS span numRow pour cet enfant avec celle calculée.
  }

  resizeAllGridItems() { // @bugfix Un premier calcul peut s'avérer insufisant, causant des bugs de rendu sur la longeur des items.
    this.grid.style.alignItems = 'start' // modification temporaire de la propriété css slign-items pour calculer la hauteur du contenu.
    this.gridItems.forEach(item => this.resizeGridItem(item)) // Appeler la fonction pour calculer le nombre de lignes dont elle a besoin.
    this.grid.style.alignItems = 'stretch' // Remettre les align-items à étirer.
  }

}

for (const masonry of document.querySelectorAll('.masonry')) {

  const grid = new VGrid(masonry)

  window.addEventListener('load', () => { // Préférable dans cette configuration à "DOMContentLoaded"
    grid.resizeAllGridItems()
    //setTimeout(() => {grid.resizeAllGridItems()}, 200) // @note Deuxième application après un premier calcul @todo Désactivée pour test.
  })

  window.addEventListener('resize', () => { // Lancement du calcul de la grille si resize
    let resizeTimeout
    clearTimeout(resizeTimeout)
    resizeTimeout = setTimeout(() => {grid.resizeAllGridItems()}, 200) // Limitation du nombre de calculs @see https://stackoverflow.com/questions/5836779/
  })

}
