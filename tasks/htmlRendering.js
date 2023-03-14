import { readdirSync, writeFileSync, readFileSync } from 'fs'
import { renderFile } from 'pug'

const files = readdirSync('views/pages/')

// Génération des icônes de démonstration (doit précéder la génération des pages)
const str = readFileSync('sprites/util.svg', 'utf8')
const names = [...str.matchAll(/id="(.*?)"/gi)].map(m => m[1]) // @note Capture l'ID de chaque symbole. Par rapport à match(), matchAll() permet de capturer les groupes. map() sort un seul résultat pour chaque itération.

function createIcons(names) {
  let icon = '//- fichier autogénéré par la commande `yarn html`'
  for (const name of names) {
    icon += `
ruby
  svg.icon.scale200(role='img' focusable='false')
    use(href='/sprites/util.svg#${name}')
  rt.scale80 ${name}`
  }
  return icon
}

writeFileSync('views/includes/iconList.pug', createIcons(names))

writeFileSync('index.html', renderFile('views/index.pug'))
writeFileSync('404.html', renderFile('views/404.pug'))

for (let file of files) {
  file = file.toString().slice(0, -4)
  writeFileSync(`page/${file}.html`, renderFile(`views/pages/${file}.pug`))
}
