import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sidebar", "toggle", "open", "label"]

  connect() {
    this.mediaQuery = window.matchMedia("(max-width: 768px)")
    this.boundMediaChange = () => {
      this.collapsed = this.mediaQuery.matches
      this.applyState(false)
    }

    this.mediaQuery.addEventListener("change", this.boundMediaChange)
    this.collapsed = this.mediaQuery.matches
    this.applyState(false)
  }

  disconnect() {
    if (this.mediaQuery && this.boundMediaChange) {
      this.mediaQuery.removeEventListener("change", this.boundMediaChange)
    }
  }

  open() {
    if (!this.collapsed) return

    this.collapsed = false
    this.applyState(true)
  }

  toggle() {
    this.collapsed = !this.collapsed
    this.applyState(true)
  }

  applyState(animate) {
    const expanded = !this.collapsed

    this.sidebarTarget.classList.toggle("w-20", !expanded)
    this.sidebarTarget.classList.toggle("w-72", expanded)

    this.labelTargets.forEach((label) => {
      if (expanded) {
        window.clearTimeout(label._collapseTimer)
        label.classList.remove("opacity-0", "pointer-events-none")

        if (!animate) {
          label.classList.remove("max-w-0")
        }

        return
      }

      label.classList.add("opacity-0", "pointer-events-none")
      window.clearTimeout(label._collapseTimer)
      label._collapseTimer = window.setTimeout(() => {
        label.classList.add("max-w-0")
      }, 300)
    })

    this.toggleTarget.classList.toggle("opacity-0", this.collapsed)
    this.toggleTarget.classList.toggle("pointer-events-none", this.collapsed)
    this.openTarget.classList.toggle("hidden", !this.collapsed)
    this.toggleTarget.classList.toggle("hidden", this.collapsed)
  }
}