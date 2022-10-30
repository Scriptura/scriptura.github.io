'use strict'

// @documentation :
// @see https://www.thewebtaylor.com/articles/how-to-get-a-youtube-videos-thumbnail-image-in-high-quality
// API JSON:
// https://youtube.com/oembed?url=http://www.youtube.com/watch?v=SMYuFq84E9Y&format=json

const youtubeVideo = (() => {

  document.querySelectorAll('.video-youtube').forEach(e => {

    let error = false
    const id = e.dataset.id
    const url = `https://youtube.com/oembed?url=http://www.youtube.com/watch?v=${id}` // Par défaut : `&format=json` ; alternative : `&format=xml`
    const maxThumbnailUrl = `https://img.youtube.com/vi/${id}/maxresdefault.jpg`

    //fetch(maxThumbnailUrl)
    //  .then(res => {
    //    if (res.statusText === 'OK') {
    //      thumbnail = maxThumbnailUrl
    //    }
    //    throw new Error(res.statusText)
    //  })

    fetch(url)
      .then(response => response.json())
      .then(data => {
        let thumbnail = data.thumbnail_url
        //if (maxThumbnailUrl) thumbnail = maxThumbnailUrl // @todo A faire : remplacer par une image de qualité suppérieure si elle existe.
        const el = document.createElement('div')
        el.classList.add('thumbnail-youtube')
        el.style.backgroundImage = `url(${thumbnail})`
        el.innerHTML = `<button><svg role="img" focusable="false"><use href="/sprites/utils.svg#video-play"></use></svg></button><div class="video-youtube-title">${data.title}</div>`
        e.appendChild(el)
    
        el.querySelector('button').addEventListener('click', () => {
          el.remove()
          const iframe = document.createElement('iframe')
          iframe.src = `https://www.youtube.com/embed/${id}?feature=oembed&autoplay=1&enablejsapi=1`
          iframe.title = data.title
          iframe.setAttribute('allowFullScreen', '') // @todo 'allow: fullscreen' n'est pas encore supporté
          //iframe.setAttribute('allow', 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture')
          e.appendChild(iframe)
        })
      })
      .catch(error => {
        error = true
        const div = document.createElement('div')
        div.classList.add('thumbnail-youtube')
        div.innerHTML = `<div class="video-youtube-error">Erreur : Cette vidéo n'existe pas :(</div>`
        e.appendChild(div)
        console.error('There was an error!', error)
      })

  })

})()
