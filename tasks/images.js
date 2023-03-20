import { rmSync, mkdirSync, readdir } from 'fs'
import sharp from 'sharp'
import ora from 'ora'

const src = './medias/images/src/',
      dest = './medias/images/uploads/',
      sizeXXXS = 300,
      sizeXXS = 400,
      sizeXS = 600,
      sizeS = 800,
      sizeM = 1000,
      sizeL = 1500,
      sizeXL = 2000

rmSync(dest, {recursive: true}) // Suppression du dossier.
mkdirSync(dest)

readdir(src, (err, files) => {
  const spinner = ora('Begin image task...\n').start()
  files.forEach(async fileName => {
    //await mkdirSync(dest) // création d'un dossier de destination
    await webpImage(fileName)
    spinner.stop()
  })
})

// @note 80/100 est la qualité par défaut pour la fonction webp(). @see https://sharp.pixelplumbing.com/api-output#webp
// @note Performances : le fait d'opérer le traitement WebP avant ou après le resize ne change pas significtivement le temps d'exécution (test effectué le 23/08/2022 avec sharp 0.30.7).
async function webpImage(fileName) {
  const fileExt = fileName.split('.').pop()
  const name = fileName.replace(fileExt, '').replace('\.', '')
  const path = dest + name
  try {
    const img = await sharp(src + fileName)
    await img.webp({ quality: 100 }).toFile(path + '-original.webp') // .withMetadata()
    const imgWebP80 = await img.webp()
    await imgWebP80.resize({ width: sizeXXXS }).toFile(path + '-w' + sizeXXXS + '.webp')
    await imgWebP80.resize({ width: sizeXXS }).toFile(path + '-w' + sizeXXS + '.webp')
    await imgWebP80.resize({ width: sizeXS }).toFile(path + '-w' + sizeXS + '.webp')
    await imgWebP80.resize({ width: sizeS }).toFile(path + '-w' + sizeS + '.webp')
    await imgWebP80.resize({ width: sizeM }).toFile(path + '-w' + sizeM + '.webp')
    await imgWebP80.resize({ width: sizeL }).toFile(path + '-w' + sizeL + '.webp')
    await imgWebP80.resize({ width: sizeXL }).toFile(path + '-w' + sizeXL + '.webp')
    console.log(`Created ${name}`)
  }
  catch (error) {
    console.log(error)
  }
}
