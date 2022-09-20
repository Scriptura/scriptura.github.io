// @note Solution abandonnée pour le front, mais à explorer pour plus tard...
// Le script liste les images trouvées dans un dossier et crée un fichier pug en relation en vue d'établir le HTML pour chacune des images.

import fs from 'fs'
import sizeOf from 'image-size'

const fileSrc = './medias/images/src/',
      imageList = './views/includes/imageList.pug',
      imageSrc = '/medias/images/uploads/'

const files = fs.readdirSync(fileSrc)

fs.writeFile(imageList, '', err => {
  if (err) throw err
  console.log('imageList.pug: deleted content')
})

const writeFileImageList = image => {
  fs.appendFile(imageList, image, function (err) {
    if (err) throw err
    console.log('imageList.pug: created item')
  })
}

for (const file of files) {
  try {
    const dimensions = await sizeOf(fileSrc + file)
    const fileExt = await file.split('.').pop()
    const fileName = await file.replace(fileExt, '').replace('\.', '')
    const item = await `figure.figure-focus
  -
    img = {
      name: '${fileName}',
      ext: 'webp',
      typesMime: 'image/webp',
      src: '${imageSrc}',
      width: '${dimensions.width}',
      height: '${dimensions.height}',
      alt: 'Lorem ipsum.',
      caption: 'Lorem ipsum...',
      sources: []
    }
  include ../helpers/picture2
  figcaption!= img.caption
`
    await writeFileImageList(item)
  }
  catch (error) {
    console.log(error)
  }
}
