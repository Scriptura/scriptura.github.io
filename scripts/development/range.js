'use strict'

const rangeInput = (() => {
  document.querySelectorAll('.range').forEach(range => {

    const input = range.querySelector('input')
    const output = range.querySelector('output')

    function display(val){
      if (range.dataset.currency) val = new Intl.NumberFormat(range.dataset.intl, {style: 'currency', currency: range.dataset.currency}).format(val)
      else if (range.dataset.intl) stop = new Intl.NumberFormat(range.dataset.intl).format(val)
      output.textContent = val
    }

    display(input.value)

    input.oninput = function() {
      display(this.value)
    }

  })
})()

const rangeMultithumb = (() => {
  document.querySelectorAll('.range-multithumb').forEach(range => {

    const [start, stop] = range.querySelectorAll('input')
    const output = range.querySelector('output')
    const step = Number(start.getAttribute('step'))
    let valStart = Number(start.value)
    let valStop = Number(stop.value)
    let scope = Number(stop.max) - Number(stop.min)
    let percentStart = (100 / Number(stop.max)) * valStart
    let percentStop = (100 / Number(stop.max)) * valStop
    
    range.style.setProperty('--start', `${percentStart}%`)
    range.style.setProperty('--stop', `${percentStop}%`)
    output.textContent = `${valStart}-${valStop}`
    display(valStart, valStop)

    /*
    function intl(valStart, valStop){
      [valStart, valStop].forEach(ss => {
        if (range.dataset.currency) ss = new Intl.NumberFormat(range.dataset.intl, {style: 'currency', currency: range.dataset.currency}).format(ss)
        else if (range.dataset.intl) ss = new Intl.NumberFormat(range.dataset.intl).format(ss)
      })
    }
    */

    function display(valStart, valStop){
      //intl(valStart, valStop)
      /**/
      if (range.dataset.currency) valStart = new Intl.NumberFormat(range.dataset.intl, {style: 'currency', currency: range.dataset.currency}).format(valStart)
      else if (range.dataset.intl) valStop = new Intl.NumberFormat(range.dataset.intl).format(valStop)
      if (range.dataset.currency) valStop = new Intl.NumberFormat(range.dataset.intl, {style: 'currency', currency: range.dataset.currency}).format(valStop)
      else if (range.dataset.intl) valStart = new Intl.NumberFormat(range.dataset.intl).format(valStart)
      /**/
      output.textContent = `${valStart} - ${valStop}`
    }

    function startThumb(){
      valStop = Number(stop.value)
      display(this.value, valStop)
      stop.value = (valStop > Number(this.value)) ? valStop : (Number(this.value) + step)
      range.style.setProperty('--start', `${(100 / Number(stop.max)) * this.value}%`)
      range.style.setProperty('--stop', `${(100 / Number(stop.max)) * stop.value}%`)
    }

    function stopThumb(){
      valStart = Number(start.value)
      display(valStart, this.value)
      start.value = (valStart < Number(this.value)) ? valStart : (Number(this.value) - step)
      range.style.setProperty('--start', `${(100 / Number(stop.max)) * start.value}%`)
      range.style.setProperty('--stop', `${(100 / Number(stop.max)) * this.value}%`)
    }

    start.oninput = startThumb
    start.onchange = startThumb

    stop.oninput = stopThumb
    stop.onchange = stopThumb

  })
})()
