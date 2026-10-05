class ConversationThreadsController < ApplicationController
  before_action :require_authentication
  before_action :require_completed_profile
  before_action :set_personality
  before_action :set_conversation_thread, only: %i[show archive]

  def index
    @conversation_threads = @personality.conversation_threads.recent_first
    @unread_counts = Message.unread_initiatives
      .where(conversation_thread_id: @conversation_threads.select(:id))
      .group(:conversation_thread_id).count
  end

  def new
    @client_token = SecureRandom.uuid
  end

  def create
    @result = ConversationThreads::Create.call(
      personality: @personality,
      user: current_user,
      attributes: conversation_thread_params
    )

    if @result.success?
      redirect_to personality_conversation_thread_path(
        @personality,
        @result.conversation_thread
      )
    else
      @client_token = conversation_thread_params[:client_token]
      render :new, status: :unprocessable_content
    end
  end

  def show
    @conversation_thread.messages.unread_initiatives.update_all(read_at: Time.current)
    prepare_show
  end

  def archive
    ConversationThreads::Archive.call(conversation_thread: @conversation_thread)
    redirect_to personality_conversation_threads_path(@personality),
                notice: t("app.flash.conversation_thread_archived")
  end

  private

  def set_personality
    @personality = current_user.personalities.find(params[:personality_id])
  end

  def set_conversation_thread
    @conversation_thread = @personality.conversation_threads.find(params[:id])
  end

  def conversation_thread_params
    params.require(:conversation_thread).permit(:content, :client_token)
  end

  def prepare_show
    @conversation_threads = @personality.conversation_threads.recent_first
    @unread_counts = Message.unread_initiatives
      .where(conversation_thread_id: @conversation_threads.select(:id))
      .group(:conversation_thread_id).count
    @messages = @conversation_thread.messages.includes(
      :personality_version,
      :message_image,
      :attachment,
      conversation_thread: :personality
    )
    @latest_generation_run = @conversation_thread.generation_runs.order(created_at: :desc).first
    @client_token = SecureRandom.uuid
  end
end
