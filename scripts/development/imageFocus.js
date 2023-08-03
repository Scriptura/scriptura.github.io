'use strict'

const imageFocus = (() => {

  const focusItems = document.querySelectorAll('[class*=-focus]'),
        targetClass = 'picture-area',
        content = document.querySelectorAll('body > :not(.picture-area')

  const freezePage = () => {
    document.documentElement.classList.toggle('freeze')
    document.body.classList.toggle('freeze')
    content.forEach(e => e.hasAttribute('inert') ? e.removeAttribute('inert') : e.setAttribute('inert', ''))
  }

  const addButtonEnlarge = (() => {
    focusItems.forEach(focusElement => {
      const button = document.createElement('button')
      injectSvgSprite(button, 'expand')
      focusElement.appendChild(button)
      button.ariaLabel = 'enlarge'
    })
  })()

  const clickFocusItem = (() => {
    focusItems.forEach(focusElement => {
      focusElement.addEventListener('click', () => {
        cloneImage(focusElement)
        freezePage()
      })
    })
  })()

  const cloneImage = focus => {
    const image = focus.querySelector('img')
    let clone = image.cloneNode(true)
    document.body.appendChild(clone)
    clone = wrapClone(clone)
    clone = clickFocusRemove(image)
    //if (document.fullscreenEnabled) image.requestFullscreen() // @todo Fonctionnalité à développer éventuellement si elle présente un intérêt.
  }

  const wrapClone = el => {
    const wrapper = document.createElement('div')
    wrapper.classList.add(targetClass)
    el.after(wrapper, el)
    wrapper.appendChild(el)
    addButtonShrink()
  }

  const clickFocusRemove = image => {
    const el = document.getElementsByClassName(targetClass)[0]
    //const button = document.querySelector('.focus-off button')
    el.addEventListener('click', () => {
      el.remove()
      freezePage()
      image.querySelector('button').focus() // Retour du focus sur l'image cliquée au départ.
    })
  }

  const addButtonShrink = () => {
    const el = document.getElementsByClassName(targetClass)[0],
          button = document.createElement('button')
    el.appendChild(button)
    injectSvgSprite(button, 'compress')
    button.ariaLabel = 'shrink'
    button.focus()
  }

})()
