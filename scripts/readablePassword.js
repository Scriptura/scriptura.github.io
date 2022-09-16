'use strict'

const readablePassword = (() => {
  const inputs = document.querySelectorAll('.input [type=password]')
  for (const input of inputs) {
    input.parentElement.classList.add('input', 'input-password')
    const button = document.createElement('button')
    button.type = 'button'
    button.title = 'See password'
    input.after(button)
    injectSvgSprite(button, 'eye')
    button.addEventListener('click', () => {
      button.removeChild(button.querySelector('svg'))
      if (input.type === 'password') {
        input.type = 'text'
        button.title = 'Hide password'
        injectSvgSprite(button, 'eye-blocked')
      } else {
        input.type = 'password'
        button.title = 'See password'
        injectSvgSprite(button, 'eye')
      }
    })
  }
})()
