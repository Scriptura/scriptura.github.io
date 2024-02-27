'use strict'

// @see https://stackoverflow.com/questions/985272/selecting-text-in-an-element-akin-to-highlighting-with-your-mouse

const selectText = node => {
  if (document.body.createTextRange) {
    const range = document.body.createTextRange()
    range.moveToElementText(node)
    range.select()
  } else if (window.getSelection) {
    const selection = window.getSelection()
    const range = document.createRange()
    range.selectNodeContents(node)
    selection.removeAllRanges()
    selection.addRange(range)
  } else {
    console.warn('Could not select text in node: Unsupported browser.')
  }
}

const selectAndCopy = (() => {
  document.querySelectorAll('.pre > code:not(:empty)').forEach(el => {
    const button = document.createElement('button'),
      text = el.dataset.select || 'Select and copy'
    button.type = 'button'
    if (el.offsetHeight < 30) button.classList.add('copy-offset')
    el.parentElement.appendChild(button)
    button.title = text
    button.ariaLabel = text
    injectSvgSprite(button, 'copy')
    button.addEventListener('click', () => {
      selectText(el)
      if (navigator.clipboard) {
        navigator.clipboard.writeText(el.textContent)
      } else {
        document.execCommand('copy') // @note Ancienne méthode, dépréciée mais encore très bien supportée. @todo À revoir dans le temps pour la supprimer.
      }
    })
  })
})()

const addTitleCodeBlock = (() => {
  document.querySelectorAll('.pre').forEach(el => {
    const item = document.createElement('div'),
      span = document.createElement('span'),
      reqText = el.children[0].dataset.language,
      text = document.createTextNode(reqText)
    el.appendChild(item)
    injectSvgSprite(item, 'code')
    if (reqText) {
      span.appendChild(text)
      item.appendChild(span)
    }
  })
})()
