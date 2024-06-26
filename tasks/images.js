import { rmSync, mkdirSync, readdir } from 'node:fs'
import sharp from 'sharp'
import ora from 'ora'

// Hiérarchie de fichiers reflétant une situation réelle en production :
const src = './medias/images/src/'
const dest = './medias/images/uploads/'
const sizes = [100, 200, 300, 400, 600, 800, 1000, 1500, 2000]

try {
  rmSync(dest, { recursive: true }) // Suppression du dossier.
  mkdirSync(dest)
} catch (err) {
  console.error('Erreur lors de la configuration du répertoire de destination :', err)
  process.exit(1)
}

readdir(src, async (err, files) => {
  if (err) {
    console.error('Erreur lors de la lecture du répertoire source :', err)
    return
  }

  const spinner = ora('Begin image task...\n')
  spinner.start()

  try {
    for (const fileName of files) {
      await webpImage(fileName)
      spinner.text = `Created images for file "${fileName.replace(/\.[^/.]+$/, '')}"`
    }
    spinner.succeed(`Image task completed.`)
  } catch (error) {
    spinner.fail(`La tâche d'image a échoué.`)
    console.error(`Erreur pendant le traitement des images :`, error)
  } finally {
    spinner.stop()
  }
})

async function webpImage(fileName) {
  const fileExt = fileName.split('.').pop()
  const name = fileName.replace(`.${fileExt}`, '')
  const path = dest + name

  try {
    const img = sharp(`${src}${fileName}`)
    await img.webp({ quality: 100 }).toFile(`${path}.webp`)

    await Promise.all(
      sizes.map(async width => {
        await img
          .resize({ width })
          .webp({ quality: 80 })
          .toFile(`${path}-w${width}.webp`)
      }),
    )
  } catch (error) {
    console.error(`Erreur lors du traitement de ${fileName} :`, error)
    throw error // Relancer l'erreur pour être capturée par Promise.all
  }
}

