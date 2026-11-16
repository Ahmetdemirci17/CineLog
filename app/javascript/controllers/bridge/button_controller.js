import { BridgeComponent, BridgeElement } from "@hotwired/hotwire-native-bridge"

export default class extends BridgeComponent {
  static component = "button"

  connect() {
    super.connect()
    if (!this.enabled) return

    const element = new BridgeElement(this.element)
    this.send("connect", { title: element.title }, () => {
      element.click()
    })
  }

  disconnect() {
    if (this.enabled) {
      this.send("disconnect")
    }
    super.disconnect()
  }
}
