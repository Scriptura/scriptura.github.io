'use strict'

// @note Fichier permettant de tester des scripts en développement sans devoir compiler.
// @note Ce fichier est automatiquement appelé si présence de la classe '.script-test' dans la page.

const localMediaPlayer = () => {
  const media = document.querySelector('.media'),
        input = document.querySelector('#input-media')

  console.log(media.src)

  //input.addEventListener('change', () => {
  //  media.src = input.value
  //})
  
}

window.addEventListener('load', localMediaPlayer())
