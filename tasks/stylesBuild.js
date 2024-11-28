import { readdirSync, writeFileSync } from 'fs'
import stylus from 'stylus'

const date = new Date().toISOString().split('T')
const version = date[0].replace(/-/g, '') + Math.round(date[1].split('.')[0].replace(/:/g, '') / 500)
const str = readdirSync('./styles/development/main.styl', 'utf8')

stylus(str)
  .set('filename', './styles/' + version + 'main.css')
  .render(function (err, css) {
    // logic
  })
