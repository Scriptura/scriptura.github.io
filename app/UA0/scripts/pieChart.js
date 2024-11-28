'use strict'

/**
 * Renvoie un élément HTML depuis une chaine
 * @param {string} str
 * @returns {HTMLElement}
 */
function strToDom(str) {
  return document.createRange().createContextualFragment(str).firstChild
}

function easeOutExpo(x) {
  return x === 1 ? 1 : 1 - Math.pow(2, -10 * x)
}

class Point {
  constructor(x, y) {
    this.x = x
    this.y = y
  }

  toSvgPath() {
    return `${this.x} ${this.y}`
  }

  static fromAngle(angle) {
    return new Point(Math.cos(angle), Math.sin(angle))
  }
}

class PieChart extends HTMLElement {
  constructor() {
    super()
    this.shadow = this.attachShadow({ mode: 'open' })
    this.shadow.innerHTML = `
      <style>
        :host {
          display: block;
          position: relative;
        }
        svg {
          width: 100%;
          height: 100%;
        }
        path {
          cursor: pointer;
          transition: filter .3s;
        }
        path:hover,
        path.active {
          filter: brightness(0.8) sepia(1);
        }
        #labels-container {
          position: absolute;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          pointer-events: none;
        }
        .chart-label {
          position: absolute;
          padding: .2em .5em;
          white-space: nowrap;
          transform: translate(-50%, -50%);
          background-color: var(--pie-chart-background-color-label, #fff);
          color: var(--pie-chart-color-label, #000);
          border-radius: 3px;
          opacity: 0;
          transition: opacity 0.5s ease;
          pointer-events: none;
        }
        .chart-label.visible {
          opacity: 1;
        }
      </style>
      <svg viewBox="-1 -1 2 2">
        <g mask="url(#graphMask)"></g>
        <mask id="graphMask">
          <rect fill="white" x="-1" y="-1" width="2" height="2"/>
          <circle r="0.7" fill="black"/>
        </mask>
      </svg>
      <div id="labels-container"></div>
    `
  }

  static get observedAttributes() {
    return ['data']
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (name === 'data' && oldValue !== newValue) {
      this.initializeChart()
      this.startAnimation()
    }
  }

  connectedCallback() {
    this.initializeChart()
    this.startAnimation()
  }

  parseChartData() {
    try {
      const defaultColors = [
        'hsl(210, 100%, 50%)',
        'hsl(210, 100%, 60%)',
        'hsl(210, 100%, 70%)',
        'hsl(210, 100%, 80%)',
        'hsl(210, 100%, 90%)',
      ]

      const rawData = JSON.parse(this.getAttribute('data') || '[]')
      return rawData.map((item, index) => ({
        value: parseFloat(item.value) || 0,
        label: item.label || `Section ${index + 1}`,
        color: item.color || defaultColors[index % defaultColors.length],
      }))
    } catch (e) {
      console.error('Invalid data format:', e)
      return []
    }
  }

  initializeChart() {
    this.chartData = this.parseChartData()
    const svg = this.shadow.querySelector('svg')
    const pathGroup = svg.querySelector('g')
    const maskGroup = svg.querySelector('mask')
    const labelsContainer = this.shadow.getElementById('labels-container')
    const donut = this.getAttribute('donut') ?? '0.7'
    const gap = this.getAttribute('gap') ?? '0.04'

    // Nettoyage des éléments existants
    pathGroup.innerHTML = ''
    maskGroup.innerHTML = `
      <rect fill="white" x="-1" y="-1" width="2" height="2"/>
      <circle r="${donut}" fill="black"/>
    `
    labelsContainer.innerHTML = ''

    // Création des chemins
    this.paths = this.chartData.map((item, k) => {
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
      path.setAttribute('fill', `var(--pie-chart-color-item-${item.label.replace(/ /, '').toLowerCase()}, ${item.color})`)
      path.addEventListener('mouseover', () => this.handlePathHover(k))
      path.addEventListener('mouseout', () => this.handlePathOut(k))
      pathGroup.appendChild(path)
      return path
    })

    // Création des lignes
    this.lines = this.chartData.map(() => {
      const line = document.createElementNS('http://www.w3.org/2000/svg', 'line')
      line.setAttribute('stroke', '#000')
      line.setAttribute('stroke-width', gap)
      line.setAttribute('x1', '0')
      line.setAttribute('y1', '0')
      maskGroup.appendChild(line)
      return line
    })

    // Création des labels
    this.labels = this.chartData.map((item, index) => {
      const label = document.createElement('div')
      label.id = `label${index}`
      label.className = 'chart-label'
      label.textContent = `${item.label} ${item.value}`
      label.setAttribute('tabindex', '0')
      labelsContainer.appendChild(label)
      return label
    })
  }

  startAnimation() {
    const now = Date.now()
    const duration = 1000
    const draw = () => {
      const t = (Date.now() - now) / duration
      if (t < 1) {
        this.draw(easeOutExpo(t))
        window.requestAnimationFrame(draw)
      } else {
        this.draw(1)
        this.labels.forEach(label => label.classList.add('visible'))
      }
    }
    window.requestAnimationFrame(draw)
  }

  draw(progress = 1) {
    const total = this.chartData.reduce((acc, item) => acc + item.value, 0)
    const patch = 0.0000001
    let angle = Math.PI / -2
    let start = new Point(0, -1)

    for (let k = 0; k < this.chartData.length; k++) {
      this.lines[k].setAttribute('x2', start.x)
      this.lines[k].setAttribute('y2', start.y)
      const ratio = (this.chartData[k].value / total) * progress

      if (progress === 1) {
        this.positionLabel(this.labels[k], angle + ratio * Math.PI)
      }

      angle += ratio * 2 * Math.PI - patch
      const end = Point.fromAngle(angle)
      const largeFlag = ratio > 0.5 ? '1' : '0'
      this.paths[k].setAttribute('d', `M 0 0 L ${start.toSvgPath()} A 1 1 0 ${largeFlag} 1 ${end.toSvgPath()} L 0 0`)
      start = end
    }
  }

  handlePathHover(k) {
    this.dispatchEvent(new CustomEvent('sectionhover', { detail: k }))
    this.labels[k]?.classList.add('active')
  }

  handlePathOut(k) {
    this.labels[k]?.classList.remove('active')
  }

  positionLabel(label, angle) {
    if (!label || angle === undefined) return
  
    const offsetFactor = 0.5
    const point = Point.fromAngle(angle)
  
    // Calcul des positions pour éloigner du centre
    let topPosition = (point.y * offsetFactor + 0.5) * 100
    let leftPosition = (point.x * offsetFactor + 0.5) * 100
  
    // Limites de position pour rester dans le SVG (0% à 100%)
    topPosition = Math.min(100, Math.max(0, topPosition))
    leftPosition = Math.min(100, Math.max(0, leftPosition))
  
    label.style.top = `${topPosition}%`
    label.style.left = `${leftPosition}%`
  }
}

customElements.define('pie-chart', PieChart)
