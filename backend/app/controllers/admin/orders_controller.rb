class Admin::OrdersController < ApplicationController
  before_action :require_admin!

  def index
    orders = Order.includes(:user, :payment, :shipment).order(created_at: :desc)
    orders = orders.where(status: params[:status]) if params[:status].present?
    orders = orders.where("order_number LIKE ?", "%#{Order.sanitize_sql_like(params[:q].to_s)}%") if params[:q].present?
    render json: { success: true, data: { orders: orders.map { |order| serialize(order) } }, message: "Order berhasil diambil." }
  end

  def show
    render json: { success: true, data: { order: serialize(Order.includes(:user, :payment, :shipment, :order_items, :cancellation_requests).find(params[:id])) }, message: "Detail order berhasil diambil." }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "ORDER_NOT_FOUND", "Order tidak ditemukan.")
  end

  private

  def serialize(order)
    { id: order.id, order_number: order.order_number, status: order.status, customer_name: order.user.name, total_amount: order.total_amount, payment_status: order.payment&.status, shipment: order.shipment && { id: order.shipment.id, status: order.shipment.status, tracking_number: order.shipment.tracking_number, shipped_at: order.shipment.shipped_at&.iso8601, delivered_at: order.shipment.delivered_at&.iso8601 }, cancellation_requests: order.cancellation_requests.order(created_at: :desc).map { |item| { id: item.id, status: item.status, reason: item.reason, admin_note: item.admin_note } } }
  end
end
