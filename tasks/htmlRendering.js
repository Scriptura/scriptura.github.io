import { rmSync, mkdirSync, readdirSync, writeFileSync, readFileSync } from 'fs'
import { renderFile } from 'pug'

const files = readdirSync('views/pages/')

// Génération des icônes de démonstration (doit précéder la génération des pages)
const spriteUtil = readFileSync('sprites/util.svg', 'utf8')
const spritePlayer = readFileSync('sprites/player.svg', 'utf8')

function createIcons(sprites, path) {
  const names = [...sprites.matchAll(/id="(.*?)"/gi)].map(m => m[1]) // @note Capture l'ID de chaque symbole. Par rapport à match(), matchAll() permet de capturer les groupes. map() sort un seul résultat pour chaque itération.
  let icon = '//- Fichier autogénéré par la commande `pnpm icon`'
  for (const name of names) {
    icon += `
ruby
  svg.icon(role='img' focusable='false')
    use(href='/sprites/${path}.svg#${name}')
  rt ${name}`
  }
  return icon
}

writeFileSync('views/includes/iconListUtil.pug', createIcons(spriteUtil, 'util'))
writeFileSync('views/includes/iconListPlayer.pug', createIcons(spritePlayer, 'player'))

writeFileSync('index.html', renderFile('views/index.pug'))
writeFileSync('404.html', renderFile('views/404.pug'))

rmSync('page', {recursive: true}) // Suppression du dossier ; évite la persistance d'un rendu en .html d'un fichier .pug supprimé ou renommé.
mkdirSync('page') // Recréation du dossier.

for (let file of files) {
  file = file.toString().slice(0, -4) // @note Récupération du nom de la page sans l'extension.
  writeFileSync(`page/${file}.html`, renderFile(`views/pages/${file}.pug`))
}
