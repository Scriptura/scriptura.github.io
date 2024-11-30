import { rmSync, mkdirSync } from 'fs'

const folder = 'medias/icons/dest'

rmSync(folder, {recursive: true}) // Suppression du dossier.
mkdirSync(folder) // Recréation du dossier.
