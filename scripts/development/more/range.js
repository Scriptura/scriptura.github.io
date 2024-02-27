'use strict'

const rangeInput = (() => {
  document.querySelectorAll('.range').forEach((range) => {
    const input = range.querySelector('input')
    const output = range.querySelector('output')
    const δ = Math.abs(Number(input.min)) + Number(input.max) // Calcul de la plage, le premier chiffre doit passer en possitif s'il est négatif, pas le deuxième.

    range.style.setProperty(
      '--percent',
      `${(100 / δ) * (input.value - input.min)}%`
    )
    display(input.value)

    function display(value) {
      if (range.dataset.currency)
        value = new Intl.NumberFormat(range.dataset.intl, {
          style: 'currency',
          currency: range.dataset.currency,
        }).format(value)
      else if (range.dataset.intl)
        stop = new Intl.NumberFormat(range.dataset.intl).format(value)
      output.textContent = value
    }

    function thumb() {
      display(input.value)
      range.style.setProperty(
        '--percent',
        `${(100 / δ) * (input.value - input.min)}%`
      )
    }

    input.oninput = thumb
    input.onchange = thumb // @note Permet un dernier calcul évitant de faire passer la valeur min au-delà de la valeur max.
  })
})()

const rangeMultithumb = (() => {
  document.querySelectorAll('.range-multithumb').forEach((range) => {
    const [start, stop] = range.querySelectorAll('input')
    const output = range.querySelector('output')
    const step = Number(start.getAttribute('step'))
    let valStart = Number(start.value)
    let valStop = Number(stop.value)
    const δ = Math.abs(Number(start.min)) + Number(start.max) // @note Calcul de la plage uniquement basé sur le premier range, les deux ranges ayant obligatoirement la même amplitude.
    //100 / δ * (input.value - input.min)
    range.style.setProperty('--start', `${(100 / δ) * (valStart - start.min)}%`)
    range.style.setProperty('--stop', `${(100 / δ) * (valStop - start.min)}%`)
    display(valStart, valStop)

    function display(valStart, valStop) {
      if (range.dataset.currency)
        valStart = new Intl.NumberFormat(range.dataset.intl, {
          style: 'currency',
          currency: range.dataset.currency,
        }).format(valStart)
      else if (range.dataset.intl)
        valStop = new Intl.NumberFormat(range.dataset.intl).format(valStop)
      if (range.dataset.currency)
        valStop = new Intl.NumberFormat(range.dataset.intl, {
          style: 'currency',
          currency: range.dataset.currency,
        }).format(valStop)
      else if (range.dataset.intl)
        valStart = new Intl.NumberFormat(range.dataset.intl).format(valStart)
      output.textContent = `${valStart} • ${valStop}`
    }

    function startThumb() {
      valStop = Number(stop.value)
      display(this.value, valStop)
      stop.value =
        valStop > Number(this.value) ? valStop : Number(this.value) + step
      range.style.setProperty(
        '--start',
        `${(100 / δ) * (this.value - start.min)}%`
      )
      range.style.setProperty(
        '--stop',
        `${(100 / δ) * (stop.value - start.min)}%`
      )
    }

    function stopThumb() {
      valStart = Number(start.value)
      display(valStart, this.value)
      start.value =
        valStart < Number(this.value) ? valStart : Number(this.value) - step
      range.style.setProperty(
        '--start',
        `${(100 / δ) * (start.value - start.min)}%`
      )
      range.style.setProperty(
        '--stop',
        `${(100 / δ) * (this.value - start.min)}%`
      )
    }

    start.oninput = startThumb
    stop.oninput = stopThumb

    start.onchange = startThumb // @note Permet un dernier calcul évitant de faire passer la valeur min au-delà de la valeur max.
    stop.onchange = stopThumb // @note Idem.
  })
})()
