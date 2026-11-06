class Admin::ShipmentsController < ApplicationController
  before_action :require_admin!

  def create
    shipment = ShipmentService.create!(order_id: params[:order_id], admin: current_user, request: request)
    render json: { success: true, data: { shipment: serialize(shipment) }, message: "Shipment berhasil dibuat." }, status: :created
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "ORDER_NOT_FOUND", "Order tidak ditemukan.")
  rescue ShipmentService::Error => error
    render_error(:unprocessable_content, error.code, error.message)
  end

  def pack
    render_result("Shipment berhasil dikemas.") { ShipmentService.pack!(id: params[:id], admin: current_user, request: request) }
  end

  def ship
    render_result("Shipment berhasil dikirim.") { ShipmentService.ship!(id: params[:id], tracking_number: params[:tracking_number], admin: current_user, request: request) }
  end

  def deliver
    render_result("Shipment berhasil ditandai delivered.") { ShipmentService.deliver!(id: params[:id], admin: current_user, request: request) }
  end

  private

  def render_result(message)
    shipment = yield
    render json: { success: true, data: { shipment: serialize(shipment) }, message: message }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "SHIPMENT_NOT_FOUND", "Shipment tidak ditemukan.")
  rescue ShipmentService::Error => error
    render_error(:unprocessable_content, error.code, error.message)
  end

  def serialize(shipment)
    { id: shipment.id, order_id: shipment.order_id, status: shipment.status, tracking_number: shipment.tracking_number, shipping_method: shipment.shipping_method.name, shipped_at: shipment.shipped_at&.iso8601, delivered_at: shipment.delivered_at&.iso8601 }
  end
end
