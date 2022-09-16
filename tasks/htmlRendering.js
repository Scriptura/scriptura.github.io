import { readdirSync, writeFileSync } from 'fs'
import { renderFile } from 'pug'

writeFileSync('index.html', renderFile('views/index.pug'))
writeFileSync('404.html', renderFile('views/404.pug'))
writeFileSync('page/styleGuide.html', renderFile('views/styleGuide.pug'))
writeFileSync('page/person.html', renderFile('views/person.pug'))
writeFileSync('page/place.html', renderFile('views/place.pug'))
writeFileSync('page/article.html', renderFile('views/article.pug'))
writeFileSync('page/imageGallery.html', renderFile('views/imageGallery.pug'))

const files = readdirSync('./views/includes/demos/pages/')

for (let file of files) {
  file = file.toString().slice(0, -4)
  writeFileSync(`page/${file}.html`, renderFile(`views/includes/demos/pages/${file}.pug`))
  //console.log('Created ' + file + '.html')
}
