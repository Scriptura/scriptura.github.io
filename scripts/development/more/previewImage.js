'use strict'

/**
 * @summary Affiche un aperçu du fichier sélectionné dans un `<input type="file">`.
 * Pour les images : prévisualisation directe. Pour les autres types : icône
 * représentative selon l'extension. Le container cible est lié à l'input via
 * `data-input-id`.
 *
 * @strategy
 * - AOT : collecte des inputs et résolution des containers à l'initialisation.
 *   Aucune requête DOM au runtime.
 * - AOT : table de lookup MIME/extension et regex compilées une seule fois au
 *   module level. Zéro recompilation à chaque appel.
 * - `URL.createObjectURL` en lieu et place de `FileReader.readAsDataURL` :
 *   blob URL O(1) sans copie mémoire ni encodage base64.
 * - Révocation systématique du blob URL précédent avant chaque preview :
 *   prévention des fuites mémoire sur sélections répétées.
 * - `replaceChildren()` pour vider le container : O(1), sans boucle DOM.
 * - Mutations DOM déclenchées uniquement si un fichier valide est présent.
 *
 * @architectural-decision
 * - Icônes référencées par chemin statique (`/medias/icons/...`). Si le
 *   système de build évolue (hash de fichiers, CDN), ces chemins devront
 *   être injectés via `data-attribute` ou variable globale plutôt qu'être
 *   en dur dans le script.
 * - Le container est cliquable pour rouvrir le sélecteur de fichier. Aucun
 *   rôle ARIA ajouté ici : à gérer côté HTML (`role="button"`, `tabindex`).
 * - `URL.createObjectURL` nécessite une révocation explicite. La stratégie
 *   retenue est : révocation au prochain `change`. Si le composant est
 *   détruit (SPA, navigation), une révocation sur `beforeunload` ou au
 *   démontage du composant est à prévoir.
 * - Pas de `DOMContentLoaded` : suppose exécution différée (`defer`) ou
 *   position en fin de `<body>`.
 */

const ICON_BASE = '/medias/icons/utilDest/'

const EXTENSION_ICONS = Object.freeze([
  { pattern: /\.(pdf)$/i, icon: 'file-pdf.svg' },
  { pattern: /\.(mp4|avi|mov|mkv|webm|ogv)$/i, icon: 'film.svg' },
  { pattern: /\.(mp3|ogg|wav|flac|aac|ape|aiff|alac|midi)$/i, icon: 'compact-disc.svg' },
])

const ICON_FALLBACK = 'file.svg'

function resolveIcon(fileName) {
  const name = fileName.toLowerCase()
  for (const { pattern, icon } of EXTENSION_ICONS) {
    if (pattern.test(name)) return ICON_BASE + icon
  }
  return ICON_BASE + ICON_FALLBACK
}

function initFilePreview() {
  const inputFileElements = document.querySelectorAll('input[type="file"]')
  if (!inputFileElements.length) return

  for (const inputFile of inputFileElements) {
    if (!inputFile.id) continue

    const previewContainer = document.querySelector(`[data-input-id="${inputFile.id}"]`)
    if (!previewContainer) continue

    let currentObjectURL = null

    inputFile.addEventListener('change', () => {
      previewContainer.replaceChildren()

      const file = inputFile.files?.[0]
      if (!file) return

      if (currentObjectURL) {
        URL.revokeObjectURL(currentObjectURL)
        currentObjectURL = null
      }

      const figure = document.createElement('figure')
      const img    = document.createElement('img')
      figure.appendChild(img)
      previewContainer.appendChild(figure)

      if (file.type.startsWith('image/')) {
        currentObjectURL = URL.createObjectURL(file)
        img.src = currentObjectURL
      } else {
        img.src = resolveIcon(file.name)
      }
    })

    previewContainer.addEventListener('click', () => inputFile.click())
  }
}

initFilePreview()
