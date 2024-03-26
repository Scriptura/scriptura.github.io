'use strict'

/**
 * Formatage du nom de l'utilisateur
 * @note Cette opération, déjà effectuée côté backend, est opérée aussi côté client pour permettre à l'utilisateur d'avoir un retour avant validation du formulaire.
 */
const formattedUsername = (() => {
  const username = document.querySelector('#input-username.assistance-username')

  function usernameFormat(username) {
    return (username.value = username.value
      .replace(/^\p{CWU}/u, char => char.toLocaleUpperCase()) // Première lettre majuscule
      .replace(/\s+/g, '__') // Remplacement des espaces par un "jeton"
      .replace(/__\p{CWU}/gu, char => char.toLocaleUpperCase()) // Majuscule derière les jetons
      .replace(/__/g, '') // Suppression des jetons, ce qui conduit à un résultat pascal case
      .normalize('NFD')
      .replace(/\p{Diacritic}/gu, '') // Suppression des accentuations
      .replace(/[^a-z0-9\-\.]/gi, '') // Supprimer tous les caractères hormis les minuscules, majuscules, chiffres, points, et tirets hauts.
      .trim())
  }

  if (username) username.addEventListener('change', () => usernameFormat(username))
})()

/**
 * Assistance dans la création d'un slug efficace pour l'URL d'un article.
 */
;(function createSlug() {
  const inputName = document.querySelector('#input-name.assistance-slug')
  const inputSlug = document.querySelector('#input-slug.assistance-slug')

  function slugFormat(inputName, inputSlug) {
    return (inputSlug.value = inputName.value
      .trim() // @note Facultatif car le titre bénéficie du même traitement.
      .toLowerCase() // .toLocaleLowerCase('fr_FR')
      .replace(/(<([^>]+)>)/gi, '')
      .replace(/æ/g, 'ae')
      .replace(/œ/g, 'oe')
      .normalize('NFD')
      .replace(/\p{Diacritic}/gu, '')
      .replace(/[^a-z0-9]/g, '-')
      .replace(/-+/g, '-')
      .replace(/-$/g, '')) // @note Un tiret peut persister si suppression d'un caractère spécial (par exemple "?") mais pas son séparateur "-", donc suppression de ce tiret.
  }
  if (inputName && inputSlug) inputName.addEventListener('input', () => slugFormat(inputName, inputSlug))
})()

/**
 * Compteur de caractères d un input/textarea
 * @param {NodeList} input Liste d'objets de champs de formulaire
 */
;function characterCounter(input) {
  const output = input.parentElement.querySelector('output')
  const maxLength = input.getAttribute('maxlength')
  const increment = () => {
    let text = input.value
    let count = text.length
    output.textContent = count
    if (maxLength) output.textContent += `/${maxLength}`
  }
  window.addEventListener('load', increment)
  input.addEventListener('input', increment)
}

document.querySelectorAll('.character-counter').forEach(input => characterCounter(input))

/**
 * Décompteur de caractères
 * @param {NodeList} input Liste d'objets de champs de formulaire
 */
 function characterCounterDecremental(input) {
  const output = input.parentElement.querySelector('output')
  const maxLength = input.getAttribute('maxlength') // Maximum number of characters allowed
  output.textContent = maxLength
  const decrement = () => {
    const text = input.value
    let count = maxLength - text.length
    output.textContent = count
  }
  window.addEventListener('load', () => decrement())
  input.addEventListener('input', () => decrement())
}

document.querySelectorAll('.character-counter-decremental').forEach(input => characterCounterDecremental(input))

/**
 * Ajuste la hauteur du champ par rapport au contenu
 * @param {NodeList} input Liste d'objets textarea
 */
function textareaAutosize(input) {
  const adjustHeight = () => {
    input.style.height = 'auto'
    //input.setAttribute('rows', Math.ceil(textarea.scrollHeight / 32))
    input.style.height = `${input.scrollHeight}px`
  }
  window.addEventListener('load', adjustHeight)
  window.addEventListener('resize', adjustHeight)
  input.addEventListener('input', adjustHeight)
}

document.querySelectorAll('textarea.autosize').forEach(textarea => textareaAutosize(textarea))
