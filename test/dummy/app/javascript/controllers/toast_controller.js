import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: { type: Number, default: 4000 } }

  connect() {
    this.element.classList.remove("opacity-0", "translate-y-2")
    this.dismissTimer = window.setTimeout(() => this.dismiss(), this.timeoutValue)
  }

  disconnect() {
    if (this.dismissTimer) window.clearTimeout(this.dismissTimer)
  }

  dismiss() {
    this.element.classList.add("opacity-0", "translate-y-2")
    window.setTimeout(() => this.element.remove(), 200)
  }
}
