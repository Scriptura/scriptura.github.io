'use strict'

function previewImage(event, previewContainer) {
  const input = event.target

  while (previewContainer.firstChild) {
    // Si un ou plusieurs éléments enfants déjà présent dans le preview.
    previewContainer.removeChild(previewContainer.firstChild)
  }

  const figureElement = document.createElement('figure')
  previewContainer.appendChild(figureElement)

  const imagePreview = document.createElement('img')
  figureElement.appendChild(imagePreview)

  if (input.files && input.files[0]) {
    const reader = new FileReader()
    const file = input.files[0]

    // Vérifier le type MIME du fichier si possible
    if (file.type && file.type.startsWith('image/')) {
      reader.onload = function (e) {
        imagePreview.src = e.target.result
      }
      reader.readAsDataURL(file)
    } else {
      // Définir des icônes personnalisées en fonction de l'extension du fichier
      const fileName = file.name.toLowerCase()
      if (/\.(pdf)$/i.test(fileName)) {
        imagePreview.src = '/medias/icons/utilDest/file-pdf.svg'
      } else if (/\.(mp4|avi|mov|mkv|webm|ogv)$/i.test(fileName)) {
        imagePreview.src = '/medias/icons/utilDest/film.svg'
      } else if (/\.(mp3|ogg|wav|flac|aac|ape|aiff|alac|midi)$/i.test(fileName)) {
        imagePreview.src = '/medias/icons/utilDest/compact-disc.svg'
      } else {
        imagePreview.src = '/medias/icons/utilDest/file.svg'
      }
    }
  }
}

const inputFileElements = document.querySelectorAll('input[type="file"]')

inputFileElements.forEach(inputFile => {
  const previewContainer = document.querySelector(`[data-input-id="${inputFile.id}"]`)

  if (!previewContainer) return

  inputFile.addEventListener('change', event => previewImage(event, previewContainer))

  previewContainer.addEventListener('click', () => {
    inputFile.click()
  })
})
