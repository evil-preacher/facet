class GenerationRunsController < ApplicationController
  before_action :require_authentication
  before_action :require_completed_profile
  before_action :set_personality
  before_action :set_conversation_thread
  before_action :set_generation_run

  def retry
    result = GenerationRuns::Retry.call(generation_run: @generation_run)

    if result.success?
      redirect_to personality_conversation_thread_path(
        @personality,
        @conversation_thread
      ), notice: t("app.flash.generation_retry_queued")
    else
      redirect_to personality_conversation_thread_path(
        @personality,
        @conversation_thread
      ), alert: result.errors.full_messages.to_sentence
    end
  end

  def stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache, no-store"
    response.headers["X-Accel-Buffering"] = "no"
    response.headers.delete("Content-Length")
    self.response_body = GenerationRuns::EventStream.new(
      generation_run: @generation_run,
      cursor: request.headers["Last-Event-ID"].presence || params[:cursor]
    )
  end

  def stop
    result = GenerationRuns::Stop.call(generation_run: @generation_run)
    redirect_to personality_conversation_thread_path(@personality, @conversation_thread),
                alert: (result.errors.full_messages.to_sentence unless result.success?)
  end

  private

  def set_personality
    @personality = current_user.personalities.find(params[:personality_id])
  end

  def set_conversation_thread
    @conversation_thread = @personality.conversation_threads.find(
      params[:conversation_thread_id]
    )
  end

  def set_generation_run
    @generation_run = @conversation_thread.generation_runs.find(params[:id])
  end
end
