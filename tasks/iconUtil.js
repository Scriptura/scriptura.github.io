import { rmSync, mkdirSync } from 'fs'

const folder = 'medias/icons/utilDest'

rmSync(folder, {recursive: true}) // Suppression du dossier.
mkdirSync(folder) // Recréation du dossier.
