class ErrorsController < ApplicationController
  def not_found
    render json: {
      success: false,
      error: {
        code: "NOT_FOUND",
        message: "Endpoint not found"
      }
    }, status: :not_found
  end
end
