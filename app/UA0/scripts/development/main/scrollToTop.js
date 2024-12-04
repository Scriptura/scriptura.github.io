function scrollToTop() {
  const footer = document.querySelector('.footer')
  const button = document.createElement('button')

  button.type = 'button'
  button.classList.add('scroll-top')
  button.setAttribute('aria-label', 'Scroll to top')

  //injectSvgSprite(button, 'arrow-up')
  const icon = `<svg focusable="false"><use href="./sprites/util.svg#arrow_upward"></use></svg>`
  button.insertAdjacentHTML('beforeEnd', icon)

  footer.appendChild(button)

  const item = document.querySelector('.scroll-top')

  button.classList.add('fade-out')

  function position() {
    const yy = window.innerHeight / 2 // @note Scroll sur la demi-hauteur d'une fenêtre avant apparition de la flèche.
    let y = window.scrollY
    if (y > yy) {
      button.classList.remove('fade-out')
      button.classList.add('fade-in')
    } else {
      button.classList.add('fade-out')
      button.classList.remove('fade-in')
    }
  }

  window.addEventListener('scroll', position)

  function scroll() {
    window.scrollTo({ top: 0 })
  }

  button.addEventListener('click', scroll, false)
}

document.addEventListener('DOMContentLoaded', () => {
  scrollToTop()
})
