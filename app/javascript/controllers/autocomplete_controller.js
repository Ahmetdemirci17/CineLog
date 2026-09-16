import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results"]
  static values = { url: String }

  connect() {
    this.boundClickOutside = this.clickOutside.bind(this)
    document.addEventListener("click", this.boundClickOutside)
    this.boundKeydown = this.keydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)
    document.removeEventListener("keydown", this.boundKeydown)
  }

  search() {
    clearTimeout(this.timeout)
    const query = this.inputTarget.value.trim()

    if (query.length < 2) {
      this.hide()
      return
    }

    this.timeout = setTimeout(() => {
      this.fetchResults(query)
    }, 200)
  }

  async fetchResults(query) {
    const url = `${this.urlValue}?query=${encodeURIComponent(query)}`
    try {
      const response = await fetch(url, {
        headers: { "X-Requested-With": "XMLHttpRequest" }
      })
      if (response.ok) {
        const html = await response.text()
        if (html.trim().length > 0) {
          this.resultsTarget.innerHTML = html
          this.show()
        } else {
          this.hide()
        }
      }
    } catch (error) {
      console.error("Autocomplete error:", error)
    }
  }

  show() {
    this.resultsTarget.classList.remove("hidden")
  }

  hide() {
    this.resultsTarget.classList.add("hidden")
    this.resultsTarget.innerHTML = ""
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hide()
    }
  }

  keydown(event) {
    if (event.key === "Escape") {
      this.hide()
    }
  }
}
