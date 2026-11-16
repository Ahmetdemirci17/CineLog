// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

let pendingScrollTopFrame = null

document.addEventListener("click", (event) => {
  const link = event.target.closest("a[data-turbo-frame]")
  if (!link) return

  pendingScrollTopFrame = link.closest("[data-turbo-scroll-top]") ? link.dataset.turboFrame : null
})

document.addEventListener("submit", (event) => {
  const form = event.target.closest("form[data-turbo-frame]")
  if (!form) return

  pendingScrollTopFrame = form.closest("[data-turbo-scroll-top]") ? form.dataset.turboFrame : null
})

document.addEventListener("turbo:frame-load", (event) => {
  if (pendingScrollTopFrame && event.target?.id === pendingScrollTopFrame) {
    pendingScrollTopFrame = null
    window.scrollTo({ top: 0, behavior: "smooth" })
  }
})

document.addEventListener("turbo:fetch-request-error", () => {
  pendingScrollTopFrame = null
})

document.addEventListener("turbo:frame-missing", (event) => {
  pendingScrollTopFrame = null
  const response = event.detail?.response
  if (response?.redirected) {
    event.preventDefault()
    event.detail.visit(response)
  }
})
