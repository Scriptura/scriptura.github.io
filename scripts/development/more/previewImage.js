'use strict'

function previewImage(event, previewContainer) {
  const input = event.target

  while (previewContainer.firstChild) { // Si un ou plusieurs éléments enfants déjà présent dans le preview.
    previewContainer.removeChild(previewContainer.firstChild)
  }

  const figureElement = document.createElement('figure')
  previewContainer.appendChild(figureElement)

  const imagePreview = document.createElement('img')
  figureElement.appendChild(imagePreview)

  if (input.files && input.files[0]) {
    const reader = new FileReader()
    reader.onload = function (e) {
      imagePreview.src = e.target.result
    }
    reader.readAsDataURL(input.files[0])
  }
}

const inputFileElements = document.querySelectorAll('input[type="file"]')

inputFileElements.forEach(inputFile => {
  inputFile.addEventListener('change', (event) => previewImage(event, previewContainer))

  const previewContainer = document.querySelector(`[data-input-id="${inputFile.id}"]`)
  previewContainer.addEventListener('click', () => {
    inputFile.click()
  })
})
