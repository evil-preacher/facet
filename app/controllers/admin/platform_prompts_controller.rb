module Admin
  class PlatformPromptsController < ApplicationController
    def index
      @active = AiPlatformPrompt.active.index_by(&:provider)
    end

    def show
      @provider = provider
      @active = AiPlatformPrompt.active_for(provider: @provider)
      @content = @active&.content.to_s
      @revisions = AiPlatformPrompt.where(provider: @provider, purpose: "conversation").order(revision: :desc)
    end

    def publish
      @provider = provider
      AiPlatformPrompt.transaction do
        revision = Ai::PlatformPrompts::Publish.call(provider: @provider, content: params.require(:content))
        audit_publish(revision)
      end
      redirect_to admin_platform_prompt_path(@provider), notice: t("admin.prompts.published"), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      @active = AiPlatformPrompt.active_for(provider: @provider)
      @content = params[:content]
      @revisions = AiPlatformPrompt.where(provider: @provider, purpose: "conversation").order(revision: :desc)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end

    def restore
      @provider = provider
      source = AiPlatformPrompt.find_by!(id: params.require(:revision_id), provider: @provider, purpose: "conversation")
      AiPlatformPrompt.transaction do
        revision = Ai::PlatformPrompts::Publish.call(provider: @provider, content: source.content)
        audit_publish(revision)
      end
      redirect_to admin_platform_prompt_path(@provider), notice: t("admin.prompts.published"), status: :see_other
    end

    private

    def provider
      value = params[:provider].to_s
      raise ActiveRecord::RecordNotFound unless AiPlatformPrompt::PROVIDERS.include?(value)

      value
    end

    def audit_resource_view
      return unless response.successful?

      AdminAuditEvent.create!(actor_user_id: current_admin.id, action: action_name,
                              target_type: "AiPlatformPrompt", target_id: (action_name == "show" ? @active&.id : nil))
    end

    def audit_publish(revision)
      AdminAuditEvent.create!(actor_user_id: current_admin.id, action: "publish_platform_prompt",
                              target_type: "AiPlatformPrompt", target_id: revision.id)
    end
  end
end
