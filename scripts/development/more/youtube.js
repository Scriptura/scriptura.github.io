'use strict'

/**
 * @documentation :
 * Script pour les vidéos Youtube sans l'aide de l'API.
 * Nous nous contentons ici de lire des vidéos et d'afficher leur titre. Pas de taĉhes complexes, liste de lecture ou de fonction recherche.
 * Nous pouvons donc utiliser le format JSON exposé gratuitement, ce qui permet d'éviter les limitations du nombre de requêtes imposées par les quotas de l'API Youtube et aussi de devoir utiliser une clef d'identification pour notre script.
 *
 * Sur les thumbnails :
 * @see https://www.thewebtaylor.com/articles/how-to-get-a-youtube-videos-thumbnail-image-in-high-quality
 * API JSON :
 * @see https://stackoverflow.com/questions/10066638/get-youtube-information-via-json-for-single-video-not-feed-in-javascript
 * Format de l'url JSON :
 * @see https://youtube.com/oembed?url=http://www.youtube.com/watch?v=SMYuFq84E9Y&format=json
 */

const youtubeVideo = (() => {
  document.querySelectorAll('.video-youtube').forEach((e) => {
    const id = e.dataset.id
    const json = `https://youtube.com/oembed?url=http://youtube.com/watch?v=${id}` // Par défaut : `&format=json` ; alternative : `&format=xml`
    //const maxThumbnail = `https://img.youtube.com/vi/${id}/maxresdefault.jpg` // Qualité pas toujours disponible.

    fetch(json)
      .then((response) => response.json())
      .then((data) => {
        const el = document.createElement('div')
        el.classList.add('thumbnail-youtube')
        el.style.backgroundImage = `url(${data.thumbnail_url})`
        el.innerHTML = `<button><svg role="img" focusable="false"><use href="/sprites/util.svg#youtube"></use></svg></button><div class="video-youtube-title">${data.title}</div>`
        e.appendChild(el)

        el.querySelector('button').addEventListener('click', () => {
          el.remove()
          const iframe = document.createElement('iframe')
          iframe.src = `https://www.youtube.com/embed/${id}?feature=oembed&autoplay=1`
          iframe.title = data.title
          iframe.setAttribute('allowFullScreen', '') // @todo 'allow: fullscreen' n'est pas encore supporté
          //iframe.setAttribute('allow', 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture')
          e.appendChild(iframe)
        })
      })
      .catch((error) => {
        const div = document.createElement('div')
        div.classList.add('thumbnail-youtube')
        div.innerHTML = `<div class="video-youtube-error">Erreur : cette vidéo n'existe pas !<br>(ou a été supprimée...)<br><svg role="img" focusable="false" class="icon scale" style="--scale:500%"><use href="/sprites/util.svg#space-invader"></use></svg></div>`
        e.appendChild(div)
        console.error('Une requête pour une vidéo YouTube a échoué.')
      })
  })
})()
