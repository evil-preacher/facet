import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = {
    url: String,
    messageId: String
  }

  connect() {
    if (!this.hasUrlValue) return

    this.source = new EventSource(this.urlValue)
    this.source.addEventListener("delta", this.appendDelta)
    this.source.addEventListener("done", this.finish)
    this.source.addEventListener("error", this.handleError)
  }

  disconnect() {
    this.source?.close()
  }

  appendDelta = (event) => {
    const message = document.getElementById(this.messageIdValue)
    const content = message?.querySelector("[data-message-content]")
    if (!content) return

    content.textContent += JSON.parse(event.data).delta
  }

  finish = () => {
    this.refresh()
  }

  handleError = (event) => {
    if (event.data) this.refresh()
  }

  refresh() {
    this.source?.close()
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
