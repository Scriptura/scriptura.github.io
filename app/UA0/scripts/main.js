/**
 * Enregistre un Service Worker pour l'application si le navigateur le supporte.
 * @see https://developer.mozilla.org/fr/docs/Web/API/Service_Worker_API/Using_Service_Workers
 * @async
 * @function
 * @returns {Promise<void>} Une promesse qui se résout lorsque l'enregistrement du Service Worker est terminé.
 */
async function registerServiceWorker() {
  if ('serviceWorker' in navigator) {
    try {
      const registration = await navigator.serviceWorker.register('/app/UA0/serviceWorker.js')

      if (registration.installing) {
        console.log('Installation du service worker en cours')
      } else if (registration.waiting) {
        console.log('Service worker installé')
      } else if (registration.active) {
        console.log('Service worker actif')
      }
    } catch (error) {
      console.error(`L'enregistrement du service worker a échoué : ${error}`)
    }
  }
}

registerServiceWorker()

// Lancement de l'impression :
;(function addPrintEventListener() {
  const printButtons = document.querySelectorAll('.cmd-print')

  for (const printButton of printButtons) {
    printButton.onclick = function () {
      window.print()
    }
  }
})()

// Ajuste la hauteur du champ par rapport au contenu
function textareaAutosize(textarea) {
  const targetForTextareas = document.querySelectorAll('.target-for-textarea')

  const adjustHeight = () => {
    textarea.style.height = 'auto'
    textarea.style.height = `${input.scrollHeight}px`
  }
  window.addEventListener('load', adjustHeight)
  window.addEventListener('resize', adjustHeight)
  textarea.addEventListener('input', adjustHeight)
  textarea.addEventListener('focus', adjustHeight)
  targetForTextareas.forEach(target => {
    target.addEventListener('change', adjustHeight)
    target.addEventListener('click', () => {
      adjustHeight()
      setTimeout(adjustHeight, 100) // un petit hack pour les mobiles...
    })
  })
}

document.querySelectorAll('textarea.autosize').forEach(textarea => textareaAutosize(textarea))
