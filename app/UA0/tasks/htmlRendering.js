import { writeFileSync } from 'fs'
import { renderFile } from 'pug'

writeFileSync('index.html', renderFile('views/index.pug'))
