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
    payment = order.payment
    shipment = order.shipment
    settings = StoreSetting.where(setting_key: %w[bank_name bank_account_name bank_account_number bank_transfer_instructions]).index_by(&:setting_key)
    { id: order.id, order_number: order.order_number, status: order.status, subtotal: order.subtotal, shipping_cost: order.shipping_cost, total_amount: order.total_amount, payment_deadline_at: order.payment_deadline_at.iso8601, items: order.order_items.map { |item| { product_name: item.product_name_snapshot, sku: item.sku_snapshot, unit_price: item.unit_price, quantity: item.quantity, subtotal: item.subtotal } }, payment: payment && { id: payment.id, amount: payment.amount, method: payment.payment_method, status: payment.status, rejection_reason: payment.rejection_reason, verified_at: payment.verified_at&.iso8601, proofs: payment.payment_proofs.order(created_at: :desc).map { |proof| { id: proof.id, status: proof.status, original_filename: proof.original_filename, uploaded_at: proof.uploaded_at.iso8601 } } }, shipment: shipment && { id: shipment.id, status: shipment.status, shipping_method: shipment.shipping_method.name, tracking_number: shipment.tracking_number, shipped_at: shipment.shipped_at&.iso8601, delivered_at: shipment.delivered_at&.iso8601 }, cancellation_requests: order.cancellation_requests.order(created_at: :desc).map { |item| { id: item.id, reason: item.reason, status: item.status, admin_note: item.admin_note, reviewed_at: item.reviewed_at&.iso8601, created_at: item.created_at.iso8601 } }, payment_instructions: settings.transform_values(&:setting_value) }
  end
end
