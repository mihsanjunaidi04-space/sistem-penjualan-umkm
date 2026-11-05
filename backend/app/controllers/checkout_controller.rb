require "digest"
require "json"

class CheckoutController < ApplicationController
  before_action :require_customer!

  def create
    key = request.headers["Idempotency-Key"].to_s.strip
    return render_error(:bad_request, "IDEMPOTENCY_KEY_REQUIRED", "Header Idempotency-Key wajib diisi.") if key.blank? || key.length > 180

    request_hash = Digest::SHA256.hexdigest(JSON.generate(checkout_params.to_h.sort.to_h))
    existing = IdempotencyKey.find_by(user_id: current_user.id, key: key)
    if existing && existing.expires_at > Time.current
      return replay_or_conflict(existing, request_hash)
    end
    existing&.destroy!

    idempotency = IdempotencyKey.create!(user: current_user, key: key, request_hash: request_hash, response_status: 102, expires_at: 24.hours.from_now)
    begin
      order = CheckoutService.call(user: current_user, shipping_method_id: checkout_params[:shipping_method_id], address_id: checkout_params[:address_id], customer_notes: checkout_params[:customer_notes])
      body = { success: true, data: { order: serialize_order(order) }, message: "Checkout berhasil." }
      idempotency.update!(response_status: 201, response_body: JSON.generate(body), resource_type: "Order", resource_id: order.id.to_s)
      render json: body, status: :created
    rescue CheckoutService::Error => error
      idempotency.destroy!
      render_error(:unprocessable_content, error.code, error.message, error.details)
    rescue ActiveRecord::RecordInvalid => error
      idempotency.destroy!
      render_error(:unprocessable_content, "VALIDATION_ERROR", "Checkout tidak dapat diproses.", error.record.errors.to_hash)
    rescue StandardError
      idempotency.destroy!
      raise
    end
  end

  private

  def checkout_params
    params.permit(:address_id, :shipping_method_id, :customer_notes)
  end

  def replay_or_conflict(idempotency, request_hash)
    return render_error(:conflict, "IDEMPOTENCY_CONFLICT", "Idempotency-Key sudah digunakan untuk payload berbeda.") unless idempotency.request_hash == request_hash
    return render_error(:conflict, "CHECKOUT_IN_PROGRESS", "Checkout dengan Idempotency-Key tersebut sedang diproses.") if idempotency.response_body.blank?

    render json: JSON.parse(idempotency.response_body), status: idempotency.response_status
  end

  def serialize_order(order)
    { id: order.id, order_number: order.order_number, status: order.status, subtotal: order.subtotal, shipping_cost: order.shipping_cost, total_amount: order.total_amount, payment_deadline_at: order.payment_deadline_at.iso8601, shipping_method: { id: order.shipping_method.id, name: order.shipping_method.name, cost: order.shipping_method.cost }, items: order.order_items.map { |item| { id: item.id, product_name: item.product_name_snapshot, sku: item.sku_snapshot, unit_price: item.unit_price, quantity: item.quantity, subtotal: item.subtotal } } }
  end
end
