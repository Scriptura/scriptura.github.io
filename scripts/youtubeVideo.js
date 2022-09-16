'use strict'

const youtubeVideo = (() => {
  document.querySelectorAll('.video-click').forEach(e => {
    const url = 'https://youtube.com/oembed?url=http://www.youtube.com/watch?v=3Bs4LOtIuxg&format=json'
    fetch(url)
    .then(res => {
      if (res.statusText === 'OK') {
        return res.text();
      }
      throw new Error(res.statusText);
    })
    .then(data => {
      output.innerHTML = data;
    })
    .catch(error => console.log(error))
    e.addEventListener('click', () => {
      const id = e.innerHTML.replace(/^.*\/vi\/(.{11}).*$/, '$1')
      e.innerHTML = e.innerHTML.replace(/^..*$/, '')
      const iframe = document.createElement('iframe')
      iframe.src = `https://www.youtube.com/embed/${id}?feature=oembed`
      iframe.title = 'test'
      iframe.setAttribute('allowFullScreen', '') // @todo 'allow: fullscreen' n'est pas encore supporté
      iframe.setAttribute('allow', 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture')
      iframe.dataset.title = 'test'
      iframe.dataset.author = 'Georges'
      e.appendChild(iframe)
    })
  })
})()
