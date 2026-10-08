class MessagesController < ApplicationController
  before_action :require_authentication
  before_action :require_completed_profile
  before_action :set_personality
  before_action :set_conversation_thread

  def create
    @result = Messages::Create.call(
      conversation_thread: @conversation_thread,
      user: current_user,
      attributes: message_params
    )
    @message = @result.message

    respond_to do |format|
      if @result.success?
        format.turbo_stream do
          @client_token = SecureRandom.uuid
          render :create
        end
        format.html do
          redirect_to personality_conversation_thread_path(
            @personality,
            @conversation_thread
          )
        end
      else
        format.turbo_stream do
          @client_token = message_params[:client_token]
          render :create, status: :unprocessable_content
        end
        format.html do
          prepare_show
          render "conversation_threads/show", status: :unprocessable_content
        end
      end
    end
  end

  def initiative_feedback
    message = @conversation_thread.messages.find(params[:id])
    raise ActiveRecord::RecordNotFound unless message.initiated_by == "personality"

    feedback = params.require(:initiative_feedback)
    raise ActionController::BadRequest unless %w[helpful irrelevant repetitive unwelcome].include?(feedback)

    Message.transaction do
      message.update!(initiative_feedback: feedback, initiative_feedback_at: Time.current)
      @personality.update!(initiative_enabled: false, initiative_email_enabled: false) if feedback == "unwelcome"
    end
    redirect_to personality_conversation_thread_path(@personality, @conversation_thread), status: :see_other
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

  def message_params
    params.require(:message).permit(:content, :client_token, :image)
  end

  def prepare_show
    @conversation_threads = @personality.conversation_threads.recent_first
    @messages = @conversation_thread.messages.includes(:personality_version, :message_image, :attachment)
    @latest_generation_run = @conversation_thread.generation_runs.order(created_at: :desc).first
    @client_token = message_params[:client_token]
  end
end
