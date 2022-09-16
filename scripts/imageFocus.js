'use strict'

const imageFocus = (() => {

  const images = document.querySelectorAll('[class*=-focus]'),
        targetClass = 'focus-off'

  const addButtonEnlarge = (() => {
    images.forEach(e => {
      const button = document.createElement('button')
      injectSvgSprite(button, 'enlarge')
      e.appendChild(button)
      button.ariaLabel = 'enlarge'
      button.classList.add('icon-enlarge')
    })
  })()

  const clickImage = (() => {
    images.forEach(e => {
      e.addEventListener('click', () => {
        cloneImage(e)
        document.body.style.overflow = 'hidden'
      })
    })
  })()

  const cloneImage = image => {
    const imgTag = image.querySelector('img')
    let clone = imgTag.cloneNode(true)
    clone.removeAttribute('width') // Les valeurs d'atributs peuvent déformer les images, notamment celles en portrait.
    clone.removeAttribute('height') // Idem.
    document.body.appendChild(clone)
    clone = wrapClone(clone)
    clone = clickFocusRemove(image)
  }

  const wrapClone = el => {
    const wrapper = document.createElement('div')
    wrapper.classList.add(targetClass)
    el.after(wrapper, el)
    wrapper.appendChild(el)
    addButtonShrink()
  }

  const clickFocusRemove = image => {
    const el = document.querySelector('.' + targetClass)
    el.addEventListener('click', () => {
      el.parentElement.removeChild(el)
      document.body.removeAttribute('style')
      image.querySelector('button').focus() // Retour du focus sur l'image cliquée au départ.
    })
  }

  const addButtonShrink = () => {
    const el = document.querySelector('.' + targetClass),
          button = document.createElement('button')
    el.appendChild(button)
    injectSvgSprite(button, 'shrink')
    button.classList.add('icon-shrink')
    button.ariaLabel = 'shrink'
    button.focus()
  }

})()
