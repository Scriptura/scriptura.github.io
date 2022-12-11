const rangeInput = (() => {
  document.querySelectorAll('.range').forEach(range => {
	  const input = range.querySelector('input')
	  const output = range.querySelector('output')
		output.textContent = input.value
		input.oninput = function() {
			output.textContent = this.value
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
    
		function display(start, stop){
      if (range.dataset.currency) start = new Intl.NumberFormat(range.dataset.intl, {style: 'currency', currency: range.dataset.currency}).format(start)
      else if (range.dataset.intl) stop = new Intl.NumberFormat(range.dataset.intl).format(stop)
      if (range.dataset.currency) stop = new Intl.NumberFormat(range.dataset.intl, {style: 'currency', currency: range.dataset.currency}).format(stop)
      else if (range.dataset.intl) start = new Intl.NumberFormat(range.dataset.intl).format(start)
		  output.textContent = `${start}-${stop}`
		}
    
		function plus(){
      valStop = Number(stop.value)
      display(this.value, valStop)
      stop.value = (valStop > Number(this.value)) ? valStop : (Number(this.value) + step)
      range.style.setProperty('--start', `${(100 / Number(stop.max)) * this.value}%`)
      range.style.setProperty('--stop', `${(100 / Number(stop.max)) * stop.value}%`)
		}

		function moins(){
      valStart = Number(start.value)
      display(valStart, this.value)
      start.value = (valStart < Number(this.value)) ? valStart : (Number(this.value) - step)
      range.style.setProperty('--start', `${(100 / Number(stop.max)) * start.value}%`)
      range.style.setProperty('--stop', `${(100 / Number(stop.max)) * this.value}%`)
		}

    start.oninput = plus
		start.onchange = plus

		stop.oninput = moins
		stop.onchange = moins

  })
})()
