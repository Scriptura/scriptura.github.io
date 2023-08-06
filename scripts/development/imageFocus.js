'use strict'

const imageFocus = (() => {

  const focusItems = document.querySelectorAll('[class*=-focus]'),
        targetClass = 'picture-area',
        content = document.querySelectorAll('body > :not(.picture-area')

  const freezePage = () => {
    document.documentElement.classList.toggle('freeze')
    //document.body.classList.toggle('freeze') // @note Ne pas proposer la classe sur le body sinon effet de scrool lors du dézoom @affected Chrome et Firefox.
    content.forEach(e => e.hasAttribute('inert') ? e.removeAttribute('inert') : e.setAttribute('inert', ''))
  }

  focusItems.forEach(item => { // Ajout d'un boutton pour le focus.
    const button = document.createElement('button')
    injectSvgSprite(button, 'maximize')
    item.appendChild(button)
    button.ariaLabel = 'enlarge'
  })

  focusItems.forEach(item => { // Gestion des clicks sur les items
    item.addEventListener('click', () => {
      cloneImage(item)
      freezePage()
    }, false)
  })

  const cloneImage = focus => {
    const image = focus.querySelector('img')
    let clone = image.cloneNode(true)
    document.body.appendChild(clone)
    clone = wrapClone(clone)
    clone = focusRemove(image)
    clone = fullscreen()
  }

  const wrapClone = clone => {
    const wrapper = document.createElement('div')
    wrapper.classList.add(targetClass)
    clone.after(wrapper, clone)
    wrapper.appendChild(clone)
    addButtons()
  }
  
  const fullscreen = () => {
    const fullscreenButton = document.querySelector('.picture-area button')
    const image = document.querySelector('.picture-area img')
    document.fullscreenEnabled && fullscreenButton.addEventListener('click', () => {
      image.requestFullscreen()
    }, false)
  }
  
  const focusRemove = image => {
    const el = document.getElementsByClassName(targetClass)[0],
          button = image.parentElement.parentElement.querySelector('button')
    el.addEventListener('click', () => {
      el.remove()
      freezePage()
      button.focus() // @note Retour du focus sur le bouton de l'image cliquée au départ.
    }, false)
  }

  const addButtons = () => {
    const el = document.getElementsByClassName(targetClass)[0],
          fullscreenButton = document.createElement('button'),
          shrinkButton = document.createElement('button')

    el.appendChild(fullscreenButton)
    injectSvgSprite(fullscreenButton, 'expand')
    fullscreenButton.ariaLabel = 'fullscreen'

    el.appendChild(shrinkButton)
    injectSvgSprite(shrinkButton, 'minimize')
    shrinkButton.ariaLabel = 'shrink'
    shrinkButton.focus()
  }

})()
