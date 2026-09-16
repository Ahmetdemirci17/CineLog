import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["track", "prevBtn", "nextBtn"]

  connect() {
    this.boundUpdateButtons = this.updateButtons.bind(this)
    this.trackTarget.addEventListener("scroll", this.boundUpdateButtons, { passive: true })
    // Initial check
    setTimeout(() => this.updateButtons(), 100)
  }

  disconnect() {
    if (this.hasTrackTarget) {
      this.trackTarget.removeEventListener("scroll", this.boundUpdateButtons)
    }
  }

  scrollLeft() {
    const amount = this.getScrollAmount()
    this.trackTarget.scrollBy({ left: -amount, behavior: "smooth" })
  }

  scrollRight() {
    const amount = this.getScrollAmount()
    this.trackTarget.scrollBy({ left: amount, behavior: "smooth" })
  }

  getScrollAmount() {
    return Math.max(300, Math.floor(this.trackTarget.clientWidth * 0.75))
  }

  updateButtons() {
    if (!this.hasTrackTarget || !this.hasPrevBtnTarget || !this.hasNextBtnTarget) return

    const { scrollLeft, scrollWidth, clientWidth } = this.trackTarget
    const isAtStart = scrollLeft <= 10
    const isAtEnd = scrollLeft + clientWidth >= scrollWidth - 10

    if (isAtStart) {
      this.prevBtnTarget.classList.add("opacity-30", "cursor-not-allowed")
      this.prevBtnTarget.classList.remove("hover:border-purple-500/40", "hover:text-white", "hover:bg-[#20212a]", "active:scale-95")
    } else {
      this.prevBtnTarget.classList.remove("opacity-30", "cursor-not-allowed")
      this.prevBtnTarget.classList.add("hover:border-purple-500/40", "hover:text-white", "hover:bg-[#20212a]", "active:scale-95")
    }

    if (isAtEnd) {
      this.nextBtnTarget.classList.add("opacity-30", "cursor-not-allowed")
      this.nextBtnTarget.classList.remove("hover:border-purple-500/40", "hover:text-white", "hover:bg-[#20212a]", "active:scale-95")
    } else {
      this.nextBtnTarget.classList.remove("opacity-30", "cursor-not-allowed")
      this.nextBtnTarget.classList.add("hover:border-purple-500/40", "hover:text-white", "hover:bg-[#20212a]", "active:scale-95")
    }
  }
}
