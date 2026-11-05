class OrdersController < ApplicationController
  before_action :require_customer!

  def index
    orders = current_user.orders.includes(:shipping_method, :order_items).order(created_at: :desc)
    render json: { success: true, data: { orders: orders.map { |order| serialize_order(order) } }, message: "Pesanan berhasil diambil." }
  end

  def show
    order = current_user.orders.find(params[:id])
    render json: { success: true, data: { order: serialize_order(order) }, message: "Detail pesanan berhasil diambil." }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "ORDER_NOT_FOUND", "Pesanan tidak ditemukan.")
  end

  private

  def serialize_order(order)
    { id: order.id, order_number: order.order_number, status: order.status, subtotal: order.subtotal, shipping_cost: order.shipping_cost, total_amount: order.total_amount, payment_deadline_at: order.payment_deadline_at.iso8601, items: order.order_items.map { |item| { product_name: item.product_name_snapshot, sku: item.sku_snapshot, unit_price: item.unit_price, quantity: item.quantity, subtotal: item.subtotal } } }
  end
end
