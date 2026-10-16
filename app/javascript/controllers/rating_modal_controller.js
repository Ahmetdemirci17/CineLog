import { Controller } from "@hotwired/stimulus"

const RATING_LABELS = {
  1: "1 / 10 • Felaket",
  2: "2 / 10 • Çok Kötü",
  3: "3 / 10 • Kötü",
  4: "4 / 10 • Zayıf",
  5: "5 / 10 • Ortalama",
  6: "6 / 10 • Fena Değil",
  7: "7 / 10 • İyi",
  8: "8 / 10 • Çok İyi",
  9: "9 / 10 • Harika",
  10: "10 / 10 • Başyapıt! 🏆"
}

export default class extends Controller {
  static targets = [
    "modal",
    "form",
    "formMethod",
    "tmdbIdInput",
    "mediaTypeInput",
    "titleInput",
    "posterPathInput",
    "statusInput",
    "ratingInput",
    "titleDisplay",
    "mediaTypeBadge",
    "posterDisplay",
    "posterFallback",
    "starsContainer",
    "star",
    "ratingFeedback",
    "submitRatingBtn",
    "submitRatingText"
  ]

  connect() {
    this.selectedRating = null
    this.boundHandleGlobalClick = this.handleGlobalClick.bind(this)
    document.addEventListener("click", this.boundHandleGlobalClick)

    this.boundKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)

    this.boundWindowOpen = (event) => {
      if (event.detail) this.open(event.detail)
    }
    window.addEventListener("open-rating-modal", this.boundWindowOpen)
  }

  disconnect() {
    document.removeEventListener("click", this.boundHandleGlobalClick)
    document.removeEventListener("keydown", this.boundKeydown)
    window.removeEventListener("open-rating-modal", this.boundWindowOpen)
  }

  handleGlobalClick(event) {
    const trigger = event.target.closest("[data-rating-modal-trigger]")
    if (trigger) {
      event.preventDefault()
      this.open({
        tmdbId: trigger.dataset.tmdbId,
        mediaType: trigger.dataset.mediaType,
        title: trigger.dataset.title,
        posterPath: trigger.dataset.posterPath,
        posterUrl: trigger.dataset.posterUrl,
        watchlistId: trigger.dataset.watchlistId,
        currentRating: trigger.dataset.currentRating
      })
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape" && !this.modalTarget.classList.contains("hidden")) {
      this.close()
    }
  }

  open(data) {
    const { tmdbId, mediaType, title, posterPath, posterUrl, watchlistId, currentRating } = data

    // Configure form method and action URL
    if (watchlistId && watchlistId.trim() !== "") {
      this.formTarget.action = `/watchlists/${watchlistId}`
      this.formMethodTarget.value = "patch"
    } else {
      this.formTarget.action = "/watchlists"
      this.formMethodTarget.value = "post"
    }

    // Set hidden inputs
    this.tmdbIdInputTarget.value = tmdbId || ""
    this.mediaTypeInputTarget.value = mediaType || "movie"
    this.titleInputTarget.value = title || ""
    this.posterPathInputTarget.value = posterPath || ""
    this.statusInputTarget.value = "watched"

    // Set preview details
    this.titleDisplayTarget.textContent = title || "Yapım"
    this.mediaTypeBadgeTarget.textContent = (mediaType === "tv") ? "Dizi" : "Film"

    if (posterUrl && posterUrl.trim() !== "") {
      this.posterDisplayTarget.src = posterUrl
      this.posterDisplayTarget.classList.remove("hidden")
      this.posterFallbackTarget.classList.add("hidden")
    } else {
      this.posterDisplayTarget.classList.add("hidden")
      this.posterFallbackTarget.classList.remove("hidden")
    }

    // Rating setup
    if (currentRating && parseInt(currentRating, 10) > 0) {
      this.selectedRating = parseInt(currentRating, 10)
      this.ratingInputTarget.value = this.selectedRating
    } else {
      this.selectedRating = null
      this.ratingInputTarget.value = ""
    }

    this.renderStarsState(this.selectedRating)

    // Open modal
    this.modalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.modalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  hoverStar(event) {
    const rating = parseInt(event.currentTarget.dataset.rating, 10)
    this.renderStarsState(rating, true)
  }

  resetHover() {
    this.renderStarsState(this.selectedRating, false)
  }

  selectStar(event) {
    const rating = parseInt(event.currentTarget.dataset.rating, 10)
    if (this.selectedRating === rating) {
      // Toggle off if already selected
      this.selectedRating = null
      this.ratingInputTarget.value = ""
    } else {
      this.selectedRating = rating
      this.ratingInputTarget.value = rating
    }
    this.renderStarsState(this.selectedRating, false)
  }

  renderStarsState(activeRating, isHover = false) {
    const rating = activeRating || 0

    this.starTargets.forEach((star) => {
      const starRating = parseInt(star.dataset.rating, 10)
      const svg = star.querySelector("svg")
      if (starRating <= rating) {
        star.classList.add("text-amber-400", "scale-110")
        star.classList.remove("text-zinc-600", "hover:text-zinc-400")
        if (svg) svg.classList.add("fill-amber-400")
      } else {
        star.classList.remove("text-amber-400", "scale-110")
        star.classList.add("text-zinc-600")
        if (svg) svg.classList.remove("fill-amber-400")
      }
    })

    // Feedback text
    if (rating > 0) {
      this.ratingFeedbackTarget.textContent = RATING_LABELS[rating] || `★ ${rating} / 10`
      this.ratingFeedbackTarget.classList.add("text-amber-400", "font-bold")
      this.ratingFeedbackTarget.classList.remove("text-zinc-400")

      this.submitRatingBtnTarget.disabled = false
      this.submitRatingBtnTarget.classList.remove("opacity-50", "cursor-not-allowed")
      this.submitRatingTextTarget.textContent = `★ ${rating} Puan ile Kaydet`
    } else {
      this.ratingFeedbackTarget.textContent = "Puan vermek için yıldız seçin (1-10)"
      this.ratingFeedbackTarget.classList.remove("text-amber-400", "font-bold")
      this.ratingFeedbackTarget.classList.add("text-zinc-400")

      this.submitRatingBtnTarget.disabled = true
      this.submitRatingBtnTarget.classList.add("opacity-50", "cursor-not-allowed")
      this.submitRatingTextTarget.textContent = "Puanla ve Kaydet"
    }
  }

  submitRating(event) {
    if (!this.selectedRating) {
      event.preventDefault()
      return
    }
    // Form will submit with user_rating
    this.close()
  }

  submitWithoutRating(event) {
    event.preventDefault()
    this.ratingInputTarget.value = ""
    this.formTarget.requestSubmit()
    this.close()
  }
}
