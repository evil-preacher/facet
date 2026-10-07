module Admin
  class GenerationRunsController < ApplicationController
    def retry_pending
      run = GenerationRun.pending.find(params[:id])
      Operations::Diagnostics.retry_pending_run!(id: run.id)
      AdminAuditEvent.create!(actor_user_id: current_admin.id, action: "retry_pending",
                              target_type: "GenerationRun", target_id: run.id)
      redirect_to admin_generation_run_path(run), notice: t("admin.flash.run_queued"), status: :see_other
    end
  end
end
