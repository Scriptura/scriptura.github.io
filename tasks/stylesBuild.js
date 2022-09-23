import { readdirSync, writeFileSync } from 'fs'
import stylus from 'stylus'

const str = require('fs').readFileSync('./styles/development/main.styl', 'utf8')

stylus(str)
  .set('filename', 'main.css')
  .render(function(err, css) {
    // logic
  })
