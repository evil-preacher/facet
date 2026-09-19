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

    def response(model:, input:)
      @requests << { model: model, input: input }
      type, value = @queued.shift
      raise value if type == :error

      value
    end

    def stream_response(model:, input:)
      @requests << { model: model, input: input }
      type, deltas, response = @queued.shift
      raise deltas if type == :error

      deltas.each { |delta| yield delta if block_given? }
      response
    end
  end
end
