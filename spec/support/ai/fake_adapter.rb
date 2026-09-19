module Ai
  class FakeAdapter
    attr_reader :requests

    def initialize
      @requests = []
      @queued = []
    end

    def enqueue_response(text:, request_id:, usage:)
      enqueue_raw_response(Response.new(text: text, request_id: request_id, usage: usage))
    end

    def enqueue_raw_response(response)
      @queued << [ :response, response ]
    end

    def enqueue_stream(deltas:, text:, request_id:, usage:)
      @queued << [ :stream, deltas, Response.new(text: text, request_id: request_id, usage: usage) ]
    end

    def enqueue_error(error)
      @queued << [ :error, error ]
    end

    def response(model:, input:, prompt_cache_key: nil)
      record_request(model, input, prompt_cache_key)
      type, value = @queued.shift
      raise value if type == :error

      value
    end

    def stream_response(model:, input:, prompt_cache_key: nil)
      record_request(model, input, prompt_cache_key)
      type, deltas, response = @queued.shift
      raise deltas if type == :error

      deltas.each { |delta| yield delta if block_given? }
      response
    end

    private

    def record_request(model, input, prompt_cache_key)
      request = { model: model, input: input }
      request[:prompt_cache_key] = prompt_cache_key if prompt_cache_key
      @requests << request
    end
  end
end
