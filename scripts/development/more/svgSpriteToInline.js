/**
 * Remplace un élément <use> SVG par le contenu inline du symbole SVG référencé.
 *
 * Cette fonction recherche des éléments <use> avec la classe 'sprite-to-inline',
 * récupère le fichier SVG correspondant, extrait le symbole avec l'ID spécifié,
 * et remplace l'élément parent du <use> par le contenu inline du symbole SVG,
 * tout en conservant les classes CSS déjà présentes. Elle s'assure également de
 * transférer les attributs du symbole vers le SVG parent tout en évitant l'injection
 * indésirable d'attributs `xmlns`.
 *
 * @async
 * @function svgSpriteToInline
 * @returns {Promise<void>} Une promesse qui est résolue une fois le remplacement effectué.
 * @throws {Error} Lance une erreur si le fichier SVG ne peut pas être chargé ou parsé.
 */
async function svgSpriteToInline() {
  const svgUseElements = document.querySelectorAll('.sprite-to-inline use')

  for (const svgUseElement of svgUseElements) {
    const [spriteURL, symbolID] = svgUseElement.getAttribute('href').split('#')

    try {
      const response = await fetch(spriteURL)
      const svgText = await response.text()

      const parser = new DOMParser()
      const svgDocument = parser.parseFromString(svgText, 'image/svg+xml')
      const symbol = svgDocument.querySelector(`#${symbolID}`)

      if (symbol) {
        const parent = svgUseElement.parentElement

        if (parent instanceof SVGSVGElement) {
          const svgElement = parent

          //svgElement.setAttribute('xmlns', 'http://www.w3.org/2000/svg') // Attribut et valeur implicites dans un contexte de page HTML5.

          for (const attr of symbol.attributes) {
            svgElement.setAttribute(attr.name, attr.value)
          }

          while (svgElement.firstChild) {
            svgElement.removeChild(svgElement.firstChild)
          }

          for (const child of symbol.childNodes) {
            // Manipulation directe du DOM pour éviter les injections d'attributs `xmlns` sur les élements enfants, donc utilisation de la méthode `appendChild` plutôt que `innerHTML`.
            svgElement.appendChild(child.cloneNode(true))
          }
        } else {
          console.error(`L'élément parent n'est pas un SVG.`)
        }
      }
    } catch (error) {
      console.error(`Erreur lors du chargement du fichier SVG:`, error)
    }
  }

  // Déclenchement de l'événement personnalisé à la fin de la fonction
  document.dispatchEvent(new CustomEvent('svgSpriteInlined'))
}

svgSpriteToInline()
