import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    lightLabel: String,
    darkLabel: String,
    toggleLabel: String
  }

  connect() {
    this.theme = this.savedTheme() || this.systemTheme()
    this.apply()
  }

  toggle() {
    this.theme = this.theme === "dark" ? "light" : "dark"
    this.saveTheme()
    this.apply()
  }

  apply() {
    document.documentElement.dataset.theme = this.theme
    const themeLabel = this.theme === "dark" ? this.darkLabelValue : this.lightLabelValue
    this.element.textContent = this.theme === "dark" ? "☾" : "☀"
    this.element.setAttribute("aria-label", `${this.toggleLabelValue}: ${themeLabel}`)
    this.element.title = `${this.toggleLabelValue}: ${themeLabel}`
  }

  savedTheme() {
    try {
      const value = window.localStorage.getItem("facet-theme")
      return ["light", "dark"].includes(value) ? value : null
    } catch (_error) {
      return null
    }
  }

  saveTheme() {
    try {
      window.localStorage.setItem("facet-theme", this.theme)
    } catch (_error) {
      // The active theme still applies when storage is unavailable.
    }
  }

  systemTheme() {
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
  }
}
