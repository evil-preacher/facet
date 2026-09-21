module Ai
  class GenerateReply
    FLUSH_CHARACTER_INTERVAL = 64
    FLUSH_TIME_INTERVAL = 0.25
    GUARDED_ERROR_CODES = %w[already_completed already_running already_failed stopped].freeze

    Result = Data.define(:generation_run, :model_call, :error_code) do
      def success?
        error_code.nil?
      end
    end

    def self.call(**arguments)
      new(**arguments).call
    end

    def initialize(generation_run:, gateway: Gateway.default, now: Time.current,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @generation_run = generation_run
      @assistant_message = generation_run.assistant_message
      @personality = generation_run.conversation_thread.personality
      @gateway = gateway
      @now = now
      @clock = clock
      @streamed_text = +""
      @persisted_length = 0
      @last_flush_at = @clock.call
    end

    def call
      prompt = PromptBuilder.call(generation_run: generation_run)
      request = Request.call(
        user: personality.user,
        personality: personality,
        generation_run: generation_run,
        purpose: :conversation,
        model: personality.conversation_model,
        input: prompt.input,
        prompt_cache_key: prompt.prompt_cache_key,
        stream: true,
        finalize_generation_run: false,
        gateway: @gateway,
        now: @now,
        clock: @clock
      ) { |delta| persist_delta(delta) }

      return guarded_result(request) if GUARDED_ERROR_CODES.include?(request.error_code)
      return failure_result(request) unless request.success?

      completed = complete!(request.response.text)
      dispatch_message_image if completed
      Result.new(
        generation_run: generation_run,
        model_call: request.model_call,
        error_code: ("stopped" unless completed)
      )
    end

    private

    attr_reader :generation_run, :assistant_message, :personality

    def persist_delta(delta)
      generation_run.reload
      raise StoppedError, "Generation stopped" if generation_run.stopped?

      @streamed_text << delta.to_s
      flush_streamed_text if flush_due?
    end

    def flush_due?
      @persisted_length.zero? ||
        @streamed_text.length - @persisted_length >= FLUSH_CHARACTER_INTERVAL ||
        @clock.call - @last_flush_at >= FLUSH_TIME_INTERVAL
    end

    def flush_streamed_text
      assistant_message.update!(content: @streamed_text)
      @persisted_length = @streamed_text.length
      @last_flush_at = @clock.call
    end

    def complete!(text)
      GenerationRun.transaction do
        generation_run.lock!
        return false if generation_run.stopped?

        assistant_message.update!(
          content: text,
          language: LanguageDetector.call(text),
          status: :completed
        )
        generation_run.update!(status: :completed, completed_at: @now)
        if (message_image = assistant_message.message_image)
          @message_image_event = Outbox::Publish.call(
            event_key: "generate-message-image:#{message_image.id}",
            job_class: Ai::GenerateMessageImageJob,
            arguments: [ message_image.id ]
          )
        end
        true
      end
    end

    def dispatch_message_image
      return unless @message_image_event

      Outbox::Dispatcher.call(limit: 1, event_ids: [ @message_image_event.id ])
    end

    def failure_result(request)
      GenerationRun.transaction do
        generation_run.lock!
        unless generation_run.stopped?
          assistant_message.update!(status: :failed)
          generation_run.update!(
            status: :failed,
            error_code: request.error_code,
            error_message: request.model_call&.error_message,
            completed_at: @now
          )
          assistant_message.message_image&.mark_failed!(error_code: request.error_code)
        end
      end
      Result.new(
        generation_run: generation_run,
        model_call: request.model_call,
        error_code: request.error_code
      )
    end

    def guarded_result(request)
      Result.new(
        generation_run: generation_run,
        model_call: request.model_call,
        error_code: request.error_code
      )
    end
  end
end
