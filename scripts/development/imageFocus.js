'use strict'

const imageFocus = (() => {
  const focusItems = document.querySelectorAll('[class*=-focus]'),
    targetClass = 'picture-area',
    content = document.querySelectorAll('body > :not(.picture-area')

  const freezePage = () => {
    document.documentElement.classList.toggle('freeze') // @note Ne pas proposer la classe sur le body sinon effet de scrool lors du dézoom. @affected Chrome et, dans une moindre mesure, Firefox.
    content.forEach(e =>
      e.hasAttribute('inert')
        ? e.removeAttribute('inert')
        : e.setAttribute('inert', ''),
    )
  }

  const cloneImage = item => {
    const image = item.querySelector('img'),
      clone = image.cloneNode(true)
    document.body.appendChild(clone)
    wrapClone(clone)
    focusRemove(image)
    if (document.fullscreenEnabled) fullscreen(clone)
  }

  const wrapClone = clone => {
    const wrapper = document.createElement('div')
    wrapper.classList.add(targetClass)
    clone.after(wrapper, clone)
    wrapper.appendChild(clone)
    addControlButtons()
  }

  const addFocusButton = item => {
    const button = document.createElement('button')
    injectSvgSprite(button, 'maximize')
    button.ariaLabel = 'enlarge'
    item.appendChild(button)
  }

  const addControlButtons = () => {
    const el = document.getElementsByClassName(targetClass)[0],
      shrinkButton = document.createElement('button')
    const fullscreenButton = document.createElement('button')
    injectSvgSprite(shrinkButton, 'minimize')
    shrinkButton.classList.add('shrink-button')
    shrinkButton.ariaLabel = 'shrink'
    el.appendChild(shrinkButton)
    shrinkButton.focus()
    if (document.fullscreenEnabled) {
      injectSvgSprite(fullscreenButton, 'expand')
      fullscreenButton.classList.add('fullscreen-button')
      fullscreenButton.ariaLabel = 'fullscreen'
      el.appendChild(fullscreenButton)
    }
  }

  const focusEvent = item => {
    item.addEventListener('click', () => {
      cloneImage(item)
      freezePage()
    })
  }

  const focusRemove = image => {
    const el = document.getElementsByClassName(targetClass)[0],
      shrinkButton = el.querySelector('.shrink-button'),
      button = image.parentElement.parentElement.querySelector('button')
    shrinkButton.addEventListener('click', () => {
      el.remove()
      freezePage()
      button.focus() // @note Retour du focus sur le bouton de l'image cliquée au départ.
    })
  }

  const fullscreen = item => {
    const fullscreenButton = document.querySelector('.fullscreen-button')
    document.fullscreenEnabled &&
      fullscreenButton.addEventListener('click', () => item.requestFullscreen())
  }

  focusItems.forEach(item => {
    addFocusButton(item)
    focusEvent(item)
  })
})()
