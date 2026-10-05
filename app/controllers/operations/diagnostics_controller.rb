module Operations
  class DiagnosticsController < BaseController
    def show
      response.headers["Cache-Control"] = "private, no-store"
      render json: Diagnostics.call
    end

    def retry_run
      job = Diagnostics.retry_pending_run!(id: params[:id])
      render json: { status: "queued", job_id: job.job_id }, status: :accepted
    end
  end
end
