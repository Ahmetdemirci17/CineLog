import { BridgeComponent, BridgeElement } from "@hotwired/hotwire-native-bridge"

export default class extends BridgeComponent {
  static component = "form"
  static targets = ["submit"]

  connect() {
    super.connect()
    this.handleSubmitStart = () => this.submitStart()
    this.handleSubmitEnd = () => this.submitEnd()
    this.element.addEventListener("turbo:submit-start", this.handleSubmitStart)
    this.element.addEventListener("turbo:submit-end", this.handleSubmitEnd)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.handleSubmitStart)
    this.element.removeEventListener("turbo:submit-end", this.handleSubmitEnd)
    if (this.enabled) {
      this.send("disconnect")
    }
    super.disconnect()
  }

  submitTargetConnected(target) {
    if (!this.enabled) return

    const submitButton = new BridgeElement(target)
    this.send("connect", { submitTitle: submitButton.title }, () => {
      submitButton.click()
    })
  }

  submitStart() {
    if (!this.enabled) return
    this.send("submitDisabled")
  }

  submitEnd() {
    if (!this.enabled) return
    this.send("submitEnabled")
  }
}
