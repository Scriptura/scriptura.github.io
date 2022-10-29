'use strict'

const youtubeVideo = (() => {
  document.querySelectorAll('.video-youtube').forEach(e => {
    const id = e.dataset.id
    //const json = `https://youtube.com/oembed?url=http://www.youtube.com/watch?v=${id}&format=json`
    const button = document.createElement('button')
    button.classList.add('thumbnail-youtube')
    button.style.backgroundImage = `url("https://img.youtube.com/vi/${id}/maxresdefault.jpg")`
    button.innerHTML = `<svg role="img" focusable="false"><use href="/sprites/utils.svg#video-play"></use></svg>`
    e.appendChild(button)
    e.addEventListener('click', () => {
      const iframe = document.createElement('iframe')
      iframe.src = `https://www.youtube.com/embed/${id}?feature=oembed`
      iframe.title = 'test'
      iframe.setAttribute('allowFullScreen', '') // @todo 'allow: fullscreen' n'est pas encore supporté
      iframe.setAttribute('allow', 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture')
      //iframe.dataset.title = 'test'
      //iframe.dataset.author = 'Georges'
      e.appendChild(iframe)
    })
  })
})()

// https://youtube.com/oembed?url=http://www.youtube.com/watch?v=SMYuFq84E9Y&format=json
/*
const youtubeVideo = (() => {
  document.querySelectorAll('.video-youtube').forEach(e => {
    const url = `https://youtube.com/oembed?url=http://www.youtube.com/watch?v=${e.dataset.id}&format=json`
    fetch(url)
    .then(res => {
      if (res.statusText === 'OK') {
        return res.text();
      }
      throw new Error(res.statusText)
    })
    .then(data => {
      output.innerHTML = data
    })
    .catch(error => console.log(error))
    e.addEventListener('click', () => {
      //e.innerHTML = e.innerHTML.replace(/^..*$/, '')
      const iframe = document.createElement('iframe')
      iframe.src = `https://www.youtube.com/embed/${e.dataset.id}?feature=oembed`
      iframe.title = 'test'
      iframe.setAttribute('allowFullScreen', '') // @todo 'allow: fullscreen' n'est pas encore supporté
      iframe.setAttribute('allow', 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture')
      iframe.dataset.title = 'test'
      iframe.dataset.author = 'Georges'
      e.appendChild(iframe)
    })
  })
})()
*/
