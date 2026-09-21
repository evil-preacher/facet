module GenerationRuns
  class EventStream
    include Enumerable

    RETRY_MILLISECONDS = 1_000
    DEFAULT_POLL_INTERVAL = 0.25
    DEFAULT_MAX_DURATION = 25

    def initialize(generation_run:, cursor: 0, poll_interval: DEFAULT_POLL_INTERVAL,
                   max_duration: DEFAULT_MAX_DURATION, sleeper: ->(seconds) { sleep(seconds) },
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @generation_run = generation_run
      @cursor = normalize_cursor(cursor)
      @poll_interval = poll_interval
      @max_duration = max_duration
      @sleeper = sleeper
      @clock = clock
    end

    def each
      return enum_for(:each) unless block_given?

      started_at = @clock.call
      yield "retry: #{RETRY_MILLISECONDS}\n\n"

      loop do
        emitted_delta = emit_delta { |event| yield event }
        break if emit_terminal_event { |event| yield event }
        break if @clock.call - started_at >= @max_duration

        yield ": heartbeat\n\n" unless emitted_delta
        @sleeper.call(@poll_interval)
      end
    end

    private

    def normalize_cursor(cursor)
      [ Integer(cursor || 0), 0 ].max
    rescue ArgumentError, TypeError
      0
    end

    def emit_delta
      content = @generation_run.assistant_message&.reload&.content.to_s
      characters = content.each_char.to_a
      return false if characters.length <= @cursor

      delta = characters.drop(@cursor).join
      @cursor = characters.length
      yield event("delta", { delta: delta }, id: @cursor)
      true
    end

    def emit_terminal_event
      @generation_run.reload
      case @generation_run.status
      when "completed"
        image = @generation_run.assistant_message&.message_image&.reload
        return false if image&.status_pending? || image&.status_generating?

        if image&.status_ready?
          if (url = message_image_url(image))
            yield event("image", { url: url })
          else
            yield event("image_error", { code: "storage_error" })
          end
        elsif image&.status_failed?
          yield event("image_error", { code: image.error_code })
        elsif image&.status_declined?
          yield event("image_declined", {})
        end
        emit_usage { |payload| yield payload }
        yield event("done", { status: "completed" })
        true
      when "failed"
        yield event(
          "error",
          { code: @generation_run.error_code, message: @generation_run.error_message }
        )
        true
      when "stopped"
        yield event("done", { status: "stopped" })
        true
      else
        false
      end
    end

    def message_image_url(image)
      ObjectStorage::S3Store.default.presigned_url(key: image.object_key)
    rescue StandardError => error
      Rails.logger.warn("Could not sign message image id=#{image.id} error=#{error.class.name}")
      nil
    end

    def emit_usage
      model_call = @generation_run.model_calls.completed.order(created_at: :desc).first
      return unless model_call

      yield event(
        "usage",
        {
          model: model_call.response_model || model_call.model,
          input_tokens: model_call.input_tokens,
          cached_input_tokens: model_call.cached_input_tokens,
          output_tokens: model_call.output_tokens,
          cost_microusd: model_call.cost_microusd
        }
      )
    end

    def event(name, data, id: nil)
      lines = []
      lines << "id: #{id}" if id
      lines << "event: #{name}"
      lines << "data: #{JSON.generate(data)}"
      "#{lines.join("\n")}\n\n"
    end
  end
end
