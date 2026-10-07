module Admin
  class PromptTemplatesController < ApplicationController
    def index
      @keys = Ai::PromptCatalog::KEYS
      @active = AiPromptRevision.active.index_by(&:key)
    end

    def show
      @key = prompt_key
      @active = Ai::PromptCatalog.active(@key)
      @content = @active&.content || Ai::PromptCatalog.content(@key)
      @revisions = AiPromptRevision.where(key: @key).order(revision: :desc)
    end

    def publish
      key = prompt_key
      AiPromptRevision.transaction do
        revision = Ai::PromptCatalog.publish(key: key, content: params.require(:content), actor: current_admin)
        audit_publish(revision)
      end
      redirect_to admin_prompt_template_path(key), notice: t("admin.prompts.published"), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      @key = key
      @active = Ai::PromptCatalog.active(key)
      @content = params[:content]
      @revisions = AiPromptRevision.where(key: key).order(revision: :desc)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end

    def restore
      key = prompt_key
      source_content = if params.require(:revision_id) == "default"
        File.read(Rails.root.join("config/ai_prompts/#{key}.txt")).strip
      else
        AiPromptRevision.find_by!(id: params[:revision_id], key: key).content
      end
      AiPromptRevision.transaction do
        revision = Ai::PromptCatalog.publish(key: key, content: source_content, actor: current_admin)
        audit_publish(revision)
      end
      redirect_to admin_prompt_template_path(key), notice: t("admin.prompts.published"), status: :see_other
    end

    private

    def prompt_key
      key = params[:key].to_s
      raise ActiveRecord::RecordNotFound unless Ai::PromptCatalog::KEYS.include?(key)

      key
    end

    def audit_resource_view
      return unless response.successful?

      AdminAuditEvent.create!(actor_user_id: current_admin.id, action: action_name,
                              target_type: "AiPromptRevision", target_id: (action_name == "show" ? @active&.id : nil))
    end

    def audit_publish(revision)
      AdminAuditEvent.create!(actor_user_id: current_admin.id, action: "publish_prompt",
                              target_type: "AiPromptRevision", target_id: revision.id)
    end
  end
end
