import { readdirSync, writeFileSync } from 'fs'
import { minify } from 'terser'

// @see https://terser.org/docs/api-reference/

const fileSrc = './scripts/development/'

const files = readdirSync(fileSrc)

for (const file of files) {
  const data = file //await minify(file)

  writeFileSync('./scripts/' + file, data, err => {
    if (err) console.log(err)
    else console.log(file + ' written successfully')
  })
}
