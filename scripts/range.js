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

		output.textContent = `${valStart}-${valStop}`
    
		function plus(){
      valStop = Number(stop.value)
			output.textContent = `${this.value}-${valStop}`
      stop.value = (valStop > Number(this.value)) ? valStop : (Number(this.value) + step)
		}

		function moins(){
      valStart = Number(start.value)
			output.textContent = `${valStart}-${this.value}`
      start.value = (valStart < Number(this.value)) ? valStart : (Number(this.value) - step)
		}

    start.oninput = plus
		start.onchange = plus

		stop.oninput = moins
		stop.onchange = moins

  })
})()
