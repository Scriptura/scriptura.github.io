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

    fetch(url)
      .then(response => response.json())
      .then(data => {
        console.log(data)
        const button = document.createElement('button')
        button.classList.add('thumbnail-youtube')
        button.style.backgroundImage = `url(${data.thumbnail_url})` // @note Le top qualité, mais pas toujours disponible : `https://img.youtube.com/vi/${id}/maxresdefault.jpg`
        button.innerHTML = `<svg role="img" focusable="false"><use href="/sprites/utils.svg#video-play"></use></svg><p>${data.title}</p>`
        e.appendChild(button)
    
        e.addEventListener('click', () => {
          button.remove()
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
        div.innerHTML = `<p>Erreur : Cette vidéo n'existe pas :(</p>`
        e.appendChild(div)
        console.error('There was an error!', error)
      })

  })

})()
