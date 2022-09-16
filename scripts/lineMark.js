'use strict'

// @note Marqueurs pour les pages article

const lineMarks = (el => {
  // @note Pour un meilleur contrôle il est préférable de définir explicitement les items plutôt que d'utiliser le sélecteur universel '*' et de procéder par exclusion.
  const els = document.querySelectorAll('.add-line-marks > p, .add-line-marks > h2, .add-line-marks > h3, .add-line-marks > h4, .add-line-marks > h5, .add-line-marks > h6, .add-line-marks > blockquote, .add-line-marks > ul, .add-line-marks > ol, .add-line-marks > [class*=grid]')
  const lineMarksAdd = el => {
    const a = document.createElement('a')
    a.setAttribute('name', 'mark' + i)
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
})()
