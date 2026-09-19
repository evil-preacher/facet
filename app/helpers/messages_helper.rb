module MessagesHelper
  def ai_debug_ui?
    Rails.configuration.x.ai.debug_ui
  end

  def completed_model_call_for(message)
    message.generation_run_as_assistant&.model_calls&.select(&:completed?)&.max_by(&:created_at)
  end

  def model_call_debug_line(model_call)
    return if model_call.nil?

    model = model_call.response_model.presence || model_call.model
    "#{model} · #{model_call.input_tokens} in / #{model_call.output_tokens} out"
  end
end
