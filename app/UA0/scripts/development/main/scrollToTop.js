function scrollToTop() {
  const footer = document.querySelector('.footer')
  const button = document.createElement('button')
  const icon = `<svg focusable="false"><use href="./sprites/util.svg#arrow_upward"></use></svg>`

  button.type = 'button'
  button.classList.add('scroll-top', 'fade-out')
  button.setAttribute('aria-label', 'Scroll to top')
  button.insertAdjacentHTML('beforeEnd', icon)
  footer.appendChild(button)

  function position() {
    const yy = window.innerHeight / 2
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
