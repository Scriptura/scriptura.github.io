/**
 * Initialise IntersectionObserver pour ajouter la classe 'active' aux éléments avec
 * la classe 'target-is-visible' lorsqu'ils deviennent visibles dans le viewport.
 *
 * Les éléments commenceront avec la classe 'hidden' et passeront à la classe 'active'
 * lorsque 50% de l'élément sera visible dans le viewport.
 */
/*
function activateOnScroll() {
  const targetElements = document.querySelectorAll('.target-is-visible')

  const observerOptions = {
    root: null,
    rootMargin: '0px',
    threshold: 0.5,
  }

  const observer = new IntersectionObserver((entries, observer) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('start')
        observer.unobserve(entry.target)
      }
    }
  }, observerOptions)

  for (const element of targetElements) {
    observer.observe(element)
  }
}

activateOnScroll()
*/
