import { Application } from "@hotwired/stimulus"
import GenerationStreamController from "controllers/generation_stream_controller"

window.Stimulus = Application.start()
Stimulus.register("generation-stream", GenerationStreamController)
