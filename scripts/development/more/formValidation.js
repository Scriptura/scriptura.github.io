'use strict'

/**
 * @summary Validation côté client de champs typés : nom, email, URL,
 * téléphone FR. Affiche et masque des messages d'erreur inline selon
 * les règles propres à chaque type de champ.
 *
 * @strategy
 * - AOT : collecte des inputs et binding des listeners à l'initialisation.
 *   Aucune requête DOM au runtime.
 * - WeakMap<input, errorEl> : l'élément d'erreur courant est tracké par
 *   référence directe. Zéro `querySelector` lors des événements. Pas de
 *   fuite mémoire si un input est retiré du DOM.
 * - Regex compilées une seule fois au module level.
 * - `createMessageError` met à jour l'élément existant via `replaceChildren`
 *   plutôt que de supprimer/recréer : mutation DOM minimale.
 * - `registerValidator` factorise le squelette commun des quatre validateurs
 *   (querySelectorAll + deux addEventListener).
 *
 * @architectural-decision
 * - Messages d'erreur en français et en dur : à externaliser dans un objet
 *   de config ou un système i18n si le projet devient multilingue.
 * - SVG warning injecté comme string constante AOT via `insertAdjacentHTML`.
 *   Si `injectSvgSprite` devient disponible dans ce contexte, migrer vers
 *   cette API pour cohérence avec les autres scripts.
 * - Guard `!input.value` en tête des handlers `onChange` : un champ laissé
 *   vide après tentative de saisie est silencieusement nettoyé. Politique
 *   UX délibérée — à réviser si les champs deviennent obligatoires.
 * - `validationInit` pour les URLs hérite de la vérification `/@.*@/` du
 *   validateur email. Pertinence marginale pour les URLs (l'arobase peut
 *   apparaître dans le segment auth). À supprimer si des faux positifs
 *   apparaissent.
 * - `\p{CWU}` / `\p{CWL}` : propriétés Unicode "Changes When Uppercased /
 *   Lowercased". Ciblent le premier caractère sans assumer l'alphabet latin.
 *   Requièrent le flag `u`.
 * - Pas de `DOMContentLoaded` : suppose exécution différée (`defer`) ou
 *   position en fin de `<body>`.
 */

// — Constantes AOT ——————————————————————————————————————————————————————————

const CLASS_ERROR   = 'message-warning'
const CLASS_INVALID = 'invalid'
const SVG_WARNING   = `<svg class="icon-inline" role="img" focusable="false"><use href="/sprites/util.svg#warning"></use></svg>`

const RE_DIGITS          = /\d/
const RE_NAME_SPECIAL    = /[\\\/\[\]|%&!?+÷×=±_{}()<>;:,$€£¥¢*§@~`•√π¶∆^°²©®™✓#"]/
const RE_MULTI_AT        = /@.*@/
const RE_SINGLE_AT       = /@/
const RE_EMAIL           = /\S+@\S+\.\S+/
const RE_PROTOCOL        = /^https?:\/\//i
const RE_PHONE_NON_DIGIT = /(?!\+)\D/
const RE_PHONE_FR        = /^((0|0033|\+33)[1-9][0-9]{8})$/
const RE_SPACES          = / +/g
const RE_MULTI_SPACES    = /  +/g

// — Messages d'erreur ———————————————————————————————————————————————————————

const MSG = Object.freeze({
  nameTooLong:      'Entrée invalide\u00a0: chaîne de caractères trop longue.',
  nameDigits:       'Entrée invalide\u00a0: présence de caractères numériques.',
  nameSpecial:      'Entrée invalide\u00a0: présence de caractères spéciaux non autorisés.',
  multiAt:          'Entrée invalide\u00a0: présence de plusieurs arobases.',
  emailNoAt:        'Entrée invalide\u00a0: absence du caractère arobase obligatoire.',
  emailInvalid:     "Entrée invalide\u00a0: l'adresse mail n'est pas conforme.",
  urlNoProtocol:    'Entrée invalide\u00a0: il manque un protocole à votre url (https://, http://, ...).',
  urlInvalid:       "Entrée invalide\u00a0: l'url n'est pas conforme.",
  phoneChars:       'Entrée invalide\u00a0: présence de caractères non autorisés.',
  phoneFrFormat:    'Entrée invalide\u00a0: format incorrect pour la France.',
})

// — Gestion des éléments d'erreur ——————————————————————————————————————————

const errorMap = new WeakMap()

function createMessageError(input, text) {
  input.classList.add(CLASS_INVALID)
  let el = errorMap.get(input)
  if (!el) {
    el = document.createElement('div')
    el.classList.add(CLASS_ERROR)
    input.after(el)
    errorMap.set(input, el)
  }
  const p = document.createElement('p')
  p.textContent = text
  p.insertAdjacentHTML('afterbegin', SVG_WARNING)
  el.replaceChildren(p)
}

function removeMessageError(input) {
  input.classList.remove(CLASS_INVALID)
  const el = errorMap.get(input)
  if (el) {
    el.remove()
    errorMap.delete(input)
  }
}

// — Enregistrement générique ————————————————————————————————————————————————

function registerValidator(selector, { onInput, onChange }) {
  const inputs = document.querySelectorAll(selector)
  if (!inputs.length) return
  for (const input of inputs) {
    if (onInput)  input.addEventListener('input',  () => onInput(input))
    if (onChange) input.addEventListener('change', () => onChange(input))
  }
}

// — Validateur : nom ————————————————————————————————————————————————————————

function validateName(input) {
  if (input.value.length > 41) {
    createMessageError(input, MSG.nameTooLong)
  } else if (RE_DIGITS.test(input.value)) {
    createMessageError(input, MSG.nameDigits)
  } else if (RE_NAME_SPECIAL.test(input.value)) {
    createMessageError(input, MSG.nameSpecial)
  } else {
    removeMessageError(input)
  }
}

registerValidator('.validation-name', {
  onInput: validateName,
  onChange: input => {
    input.value = input.value.replace(RE_MULTI_SPACES, ' ').trim()
    input.value = input.value.replace(/^\p{CWU}/u, c => c.toLocaleUpperCase())
    validateName(input)
  },
})

// — Validateur : email ——————————————————————————————————————————————————————

registerValidator('.validation-email', {
  onInput: input => {
    if (RE_MULTI_AT.test(input.value)) {
      createMessageError(input, MSG.multiAt)
    } else {
      removeMessageError(input)
    }
  },
  onChange: input => {
    input.value = input.value.replace(RE_SPACES, '').trim()
    if (!input.value) {
      removeMessageError(input)
    } else if (!RE_SINGLE_AT.test(input.value)) {
      createMessageError(input, MSG.emailNoAt)
    } else if (!RE_EMAIL.test(input.value)) {
      createMessageError(input, MSG.emailInvalid)
    } else {
      removeMessageError(input)
    }
  },
})

// — Validateur : URL ————————————————————————————————————————————————————————

registerValidator('.validation-url', {
  onInput: input => {
    if (RE_MULTI_AT.test(input.value)) {
      createMessageError(input, MSG.multiAt)
    } else {
      removeMessageError(input)
    }
  },
  onChange: input => {
    input.value = input.value.replace(RE_SPACES, '').trim()
    input.value = input.value.replace(/^\p{CWL}/u, c => c.toLocaleLowerCase())
    if (!input.value) {
      removeMessageError(input)
      return
    }
    if (!RE_PROTOCOL.test(input.value)) {
      createMessageError(input, MSG.urlNoProtocol)
      return
    }
    try {
      new URL(input.value)
      removeMessageError(input)
    } catch {
      createMessageError(input, MSG.urlInvalid)
    }
  },
})

// — Validateur : téléphone FR ——————————————————————————————————————————————

registerValidator('.validation-phone-fr_FR', {
  onInput: input => {
    if (!input.value) {
      removeMessageError(input)
    } else if (RE_PHONE_NON_DIGIT.test(input.value)) {
      createMessageError(input, MSG.phoneChars)
    } else {
      removeMessageError(input)
    }
  },
  onChange: input => {
    input.value = input.value.replace(RE_SPACES, '').trim()
    if (!input.value) {
      removeMessageError(input)
    } else if (!RE_PHONE_FR.test(input.value)) {
      createMessageError(input, MSG.phoneFrFormat)
    } else {
      removeMessageError(input)
    }
  },
})
