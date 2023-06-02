import { rmSync, mkdirSync } from 'fs'

const folder = 'medias/icons/playerDest'

rmSync(folder, {recursive: true}) // Suppression du dossier.
mkdirSync(folder) // Recréation du dossier.
