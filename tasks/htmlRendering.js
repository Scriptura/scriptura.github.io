import { readdirSync, writeFileSync, readFileSync } from 'fs'
import { renderFile } from 'pug'

const sprites = readFileSync('sprites/util.svg', 'utf8')
//sprites.forEach(symbols => sprite)

writeFileSync('index.html', renderFile('views/index.pug'))
writeFileSync('404.html', renderFile('views/404.pug'))

const files = readdirSync('views/pages/')

for (let file of files) {
  file = file.toString().slice(0, -4)
  writeFileSync(`page/${file}.html`, renderFile(`views/pages/${file}.pug`))
  //console.log('Created ' + file + '.html')
}
