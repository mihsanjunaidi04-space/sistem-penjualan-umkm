class HealthCheckController < ApplicationController
  def index
    render json: {
      success: true,
      data: { status: 'ok' },
      message: 'Health check passed'
    }, status: :ok
  end
end
