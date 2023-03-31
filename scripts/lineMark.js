'use strict'

// @note Marqueurs pour les pages article

const lineMarks = el => {
  // @note Pour un meilleur contrôle il est préférable de définir explicitement les items plutôt que d'utiliser le sélecteur universel '*' et de procéder par exclusion.
  const els = document.querySelectorAll('.add-line-marks > :is(p, h2, h3, h4, h5, h6, blockquote, ul, ol, [class*=grid])')
  const lineMarksAdd = el => {
    const a = document.createElement('a')
    a.id = 'mark' + i
    a.setAttribute('href', '#mark' + i)
    const text = document.createTextNode(i)
    a.appendChild(text)
    a.classList.add('line-mark')
    el.appendChild(a)
  }
  let i = 0
  for (const el of els) {
    i++
    //if (i % 5 === 0) {}
    //el.classList.add('relative')
    lineMarksAdd(el)
  }
}

lineMarks()

/*
const sizeM = '800px'

if (window.matchMedia(`(width > ${sizeM})`).matches) lineMarks()

onresize = (event) => {
  setTimeout(() => {
    if (window.matchMedia(`(width > ${sizeM})`).matches) lineMarks()
  }, 200)
}
*/
