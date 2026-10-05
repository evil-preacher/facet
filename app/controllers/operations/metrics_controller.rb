module Operations
  class MetricsController < BaseController
    def show
      response.headers["Cache-Control"] = "private, no-store"
      render json: ModelMetrics.call
    end
  end
end
