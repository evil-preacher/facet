import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = {
    url: String,
    messageId: String,
    stoppedLabel: String
  }

  connect() {
    if (!this.hasUrlValue) return

    this.source = new EventSource(this.urlValue)
    this.source.addEventListener("delta", this.appendDelta)
    this.source.addEventListener("usage", this.updateUsage)
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

  updateUsage = (event) => {
    const usage = JSON.parse(event.data)
    const message = document.getElementById(this.messageIdValue)
    const debug = message?.querySelector("[data-message-debug]")
    if (!debug) return

    debug.textContent = `${usage.model} · ${usage.input_tokens} in / ${usage.output_tokens} out`
    debug.classList.remove("hidden")
  }

  finish = (event) => {
    const { status } = JSON.parse(event.data)

    this.source?.close()
    this.updateMessageStatus(status)
    document.getElementById("generation_status")?.replaceChildren()
    this.element.remove()
  }

  handleError = (event) => {
    if (event.data) this.refresh()
  }

  refresh() {
    const scrollX = window.scrollX
    const scrollY = window.scrollY

    document.addEventListener("turbo:load", () => {
      window.scrollTo(scrollX, scrollY)
    }, { once: true })

    this.source?.close()
    Turbo.visit(window.location.href, { action: "replace" })
  }

  updateMessageStatus(status) {
    const message = document.getElementById(this.messageIdValue)
    const statusElement = message?.querySelector("[data-message-status]")
    if (!statusElement) return

    if (status === "completed") {
      statusElement.remove()
    } else if (status === "stopped") {
      statusElement.textContent = this.stoppedLabelValue
    }
  }
}
