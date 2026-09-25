class MemoriesController < ApplicationController
  before_action :require_authentication
  before_action :require_completed_profile
  before_action :set_personality
  before_action :set_memory, only: %i[update destroy approve]

  def index
    load_memories
  end

  def update
    result = Memories::Replace.call(
      memory: @memory,
      user: current_user,
      attributes: memory_params
    )
    if result.success?
      redirect_to personality_memories_path(@personality), notice: t("app.flash.memory_updated")
    else
      @memory_errors = result.errors
      load_memories
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    Memories::Delete.call(memory: @memory, user: current_user)
    redirect_to personality_memories_path(@personality), notice: t("app.flash.memory_deleted")
  end

  def clear
    @personality.memories.delete_all
    redirect_to personality_memories_path(@personality), notice: t("app.flash.memories_cleared")
  end

  def approve
    Memories::Approve.call(memory: @memory, user: current_user)
    redirect_to personality_memories_path(@personality), notice: t("app.flash.memory_approved")
  end

  def settings
    @personality.update!(automatic_memory_enabled: settings_params.fetch(:automatic_memory_enabled))
    redirect_to personality_memories_path(@personality), notice: t("app.flash.memory_settings_updated")
  end

  private

  def set_personality
    @personality = current_user.personalities.find(params[:personality_id])
  end

  def set_memory
    @memory = @personality.memories.current.find(params[:id])
  end

  def load_memories
    @kind = params[:kind].presence_in(Memory::KINDS)
    current_memories = @personality.memories.current
    @memory_counts = Memory::KINDS.index_with { 0 }.merge(current_memories.group(:kind).count)
    @memory_total = @memory_counts.values.sum
    @memories = current_memories
      .then { |scope| @kind ? scope.where(kind: @kind) : scope }
      .includes(source_messages: :conversation_thread)
      .order(Arel.sql("CASE status WHEN 'pending' THEN 0 ELSE 1 END"), importance: :desc, updated_at: :desc)
  end

  def memory_params
    params.require(:memory).permit(:content, :kind, :importance)
  end

  def settings_params
    params.require(:personality).permit(:automatic_memory_enabled)
  end
end
