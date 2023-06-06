'use strict'

// @see https://www.regular-expressions.info/quickstart.html
// @see https://stackoverflow.com/questions/22937618

const formValidation = (() => {

  const classMessageError = 'message-warning'

  function createMessageError(input, el, text) {
    input.classList.add('invalid')
    if (el) el.remove()
    el = document.createElement('div')
    el.classList.add(classMessageError)
    input.after(el)
    const p = document.createElement('p')
    p.textContent = text
    const svg = `<svg class="icon-inline" role="img" focusable="false"><use href="/sprites/util.svg#warning"></use></svg>`
    p.insertAdjacentHTML('afterbegin', svg)
    el.appendChild(p)
  }

  function removeMessageError(input, el) {
    input.classList.remove('invalid')
    if (el) el.remove()
  }

  const validationName = (() => {
    document.querySelectorAll('.validation-name').forEach(input => {
      input.addEventListener('keyup', e => validationInit(input), false)
      input.addEventListener('change', e => input.value = input.value.replace(/  +/g, ' '), false) // @note Réduire les espaces internes dupliqués à un seul.
      input.addEventListener('change', e => input.value = input.value.trim(), false)
      input.addEventListener('change', e => input.value = input.value.replace(/^\p{CWU}/u, char => char.toLocaleUpperCase()), false)
      input.addEventListener('change', e => validationInit(input), false)
    })
    function validationInit(input) {
      const el = input.parentNode.querySelector('.' + classMessageError)
      if (input.value.length > 41) { // @note Il existe des noms de famille hawaïens de 35 lettres...
        let text = "Entrée invalide\u00a0: chaîne de caractères trop longue."
        createMessageError(input, el, text)
      } else if (input.value.match('\\d')) {
        let text = "Entrée invalide\u00a0: présence de caractères numériques."
        createMessageError(input, el, text)
      } else if (input.value.match('[\\\\/\\[\\]|%&!?\+÷×=±_{}()<>;:,$€£¥¢*§@~`•√π¶∆^°²©®™✓\#\"]')) { // @note Le point l'espace et les guillemets simples sont exclus du test.
        let text = "Entrée invalide\u00a0: présence de caractères spéciaux non autorisés."
        createMessageError(input, el, text)
      } else {
        removeMessageError(input, el)
      }
    }
  })()

  const validationEmail = (() => {
    document.querySelectorAll('.validation-email').forEach(input => {
      input.addEventListener('keyup', e => validationInit(input), false)
      input.addEventListener('change', e => input.value = input.value.replace(/ +/g, ''), false) // @note Suppression les espaces internes
      input.addEventListener('change', e => input.value = input.value.trim(), false)
      input.addEventListener('change', e => validationExit(input), false)
    })
    function validationInit(input) {
      const el = input.parentNode.querySelector('.' + classMessageError)
      if (input.value.match(/@.*@/)) {
        let text = "Entrée invalide\u00a0: présence de plusieurs arobases."
        createMessageError(input, el, text)
      } else {
        removeMessageError(input, el)
      }
    }
    function validationExit(input) {
      const el = input.parentNode.querySelector('.' + classMessageError)
      if (!input.value) { // @note Nettoyage du message d'erreur si au final l'utilisateur laisse le champ vide après avoir tenté de le compléter.
        removeMessageError(input, el)
      } else if (!input.value.match(/@/)) {
        let text = "Entrée invalide\u00a0: absence du caractère arobase obligatoire."
        createMessageError(input, el, text)
      } else if (!input.value.match(/\S+@\S+\.\S+/)) {
        let text = "Entrée invalide\u00a0: l'addresse mail n'est pas conforme."
        createMessageError(input, el, text)
      } else {
        removeMessageError(input, el)
      }
    }
  })()

  const validationUrl = (() => {
    document.querySelectorAll('.validation-url').forEach(input => {
      input.addEventListener('keyup', e => validationInit(input), false)
      input.addEventListener('change', e => input.value = input.value.replace(/ +/g, ''), false) // @note Suppression les espaces internes.
      input.addEventListener('change', e => input.value = input.value.trim(), false)
      input.addEventListener('change', e => input.value = input.value.replace(/^\p{CWL}/u, char => char.toLocaleLowerCase()), false) // @note Les noms de domaines et protocoles sont toujours insensibles à la case.
      input.addEventListener('change', e => validationExit(input), false)
    })
    function validationInit(input) {
      const el = input.parentNode.querySelector('.' + classMessageError)
      if (input.value.match(/@.*@/)) {
        let text = "Entrée invalide\u00a0: présence de plusieurs arobases."
        createMessageError(input, el, text)
      } else {
        removeMessageError(input, el)
      }
    }
    function validationExit(input) {
      const el = input.parentNode.querySelector('.' + classMessageError)
      let url
      try {
        new URL(input.value) // Test de la validité de l'url par une fonction js native
        url = true
      } catch (error) {
        //console.error(error)
        url = false
      }
      if (!input.value) { // Nettoyage du message d'erreur si au final l'utilisateur laisse le champ vide après avoir tenté de le compléter.
        removeMessageError(input, el)
      } else if (!input.value.match(/http/)) { // @see https://stackoverflow.com/questions/3809401#3809435
        let text = "Entrée invalide\u00a0: il manque un protocole à votre url (https://, http://, ftp://, ...)."
        createMessageError(input, el, text)
      } else if (!url) {
        let text = "Entrée invalide\u00a0: l'url n'est pas conforme."
        createMessageError(input, el, text)
      } else {
        removeMessageError(input, el)
      }
    }
  })()

  const validationPhoneFrFR = (() => {
    document.querySelectorAll('.validation-phone-fr_FR').forEach(input => {
      input.addEventListener('keyup', e => validationInit(input), false)
      input.addEventListener('change', e => input.value = input.value.replace(/ +/g, ''), false) // @note Suppression les espaces internes.
      input.addEventListener('change', e => input.value = input.value.trim(), false)
      input.addEventListener('change', e => validationExit(input), false)
    })
    function validationInit(input) {
      const el = input.parentNode.querySelector('.' + classMessageError)
      if (!input.value) { // @note Nettoyage du message d'erreur si au final l'utilisateur laisse le champ vide après avoir tenté de le compléter.
        removeMessageError(input, el)
      } else if (input.value.match(/(?!\+)\D/)) {
        let text = "Entrée invalide\u00a0: présence de caractères non autorisés."
        createMessageError(input, el, text)
      } else {
        removeMessageError(input, el)
      }
    }
    function validationExit(input) {
      const el = input.parentNode.querySelector('.' + classMessageError)
      if (!input.value) { // @note Nettoyage du message d'erreur si au final l'utilisateur laisse le champ vide après avoir tenté de le compléter.
        removeMessageError(input, el)
      //} else if (!input.value.match(/\+\D/)) {
      //  let text = "Entrée invalide\u00a0: présence de caractères non numériques."
      //  createMessageError(input, el, text)
      } else if (!input.value.match(/^((0|0033|\+33)[1-9][0-9]{8})$/)) {
        let text = "Entrée invalide\u00a0: format incorrect pour la France."
        createMessageError(input, el, text)
      } else {
        removeMessageError(input, el)
      }
    }
  })()

})()
