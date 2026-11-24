require "digest"
require "json"

class CheckoutController < ApplicationController
  before_action :require_customer!

  class IdempotencyKeyConflict < StandardError; end

  def create
    key = request.headers["Idempotency-Key"].to_s.strip
    return render_error(:bad_request, "IDEMPOTENCY_KEY_REQUIRED", "Header Idempotency-Key wajib diisi.") if key.blank? || key.length > 180

    checkout_parameters = checkout_params
    request_hash = Digest::SHA256.hexdigest(JSON.generate(checkout_parameters.to_h.sort.to_h))
    outcome = nil
    begin
      ActiveRecord::Base.transaction do
        idempotency = IdempotencyKey.find_by(user_id: current_user.id, key: key)
        if idempotency && idempotency.expires_at > Time.current
          outcome = replay_or_conflict(idempotency, request_hash)
        else
          idempotency&.destroy!
          idempotency = create_idempotency_key!(key, request_hash)
          order = CheckoutService.call(
            user: current_user,
            shipping_method_id: checkout_parameters[:shipping_method_id],
            address_id: checkout_parameters[:address_id],
            customer_notes: checkout_parameters[:customer_notes]
          )
          body = { success: true, data: { order: serialize_order(order) }, message: "Checkout berhasil." }
          idempotency.update!(response_status: 201, response_body: JSON.generate(body), resource_type: "Order", resource_id: order.id.to_s)
          outcome = { body:, status: :created }
        end
      end
    rescue CheckoutService::Error => error
      outcome = { error: [ :unprocessable_content, error.code, error.message, error.details ] }
    rescue ActiveRecord::RecordInvalid => error
      outcome = { error: [ :unprocessable_content, "VALIDATION_ERROR", "Checkout tidak dapat diproses.", error.record.errors.to_hash ] }
    rescue IdempotencyKeyConflict
      outcome = resolve_idempotency_conflict(key, request_hash)
    rescue ActiveRecord::StatementInvalid => error
      raise unless sqlite_busy_error?(error)

      outcome = resolve_sqlite_busy(key, request_hash)
    end

    render_outcome(outcome)
  end

  private

  def checkout_params
    params.permit(:address_id, :shipping_method_id, :customer_notes)
  end

  def replay_or_conflict(idempotency, request_hash)
    return { error: [ :conflict, "IDEMPOTENCY_CONFLICT", "Idempotency-Key sudah digunakan untuk payload berbeda." ] } unless idempotency.request_hash == request_hash
    return { error: [ :conflict, "CHECKOUT_IN_PROGRESS", "Checkout dengan Idempotency-Key tersebut sedang diproses." ] } if idempotency.response_body.blank?

    { body: JSON.parse(idempotency.response_body), status: idempotency.response_status }
  end

  def create_idempotency_key!(key, request_hash)
    IdempotencyKey.create!(user: current_user, key:, request_hash:, response_status: 102, expires_at: 24.hours.from_now)
  rescue ActiveRecord::RecordNotUnique
    raise IdempotencyKeyConflict
  end

  def resolve_idempotency_conflict(key, request_hash)
    idempotency = IdempotencyKey.find_by(user_id: current_user.id, key: key)
    return replay_or_conflict(idempotency, request_hash) if idempotency && idempotency.expires_at > Time.current

    { error: [ :conflict, "CHECKOUT_IN_PROGRESS", "Checkout dengan Idempotency-Key tersebut sedang diproses." ] }
  end

  def resolve_sqlite_busy(key, request_hash)
    idempotency = IdempotencyKey.find_by(user_id: current_user.id, key: key)
    return replay_or_conflict(idempotency, request_hash) if idempotency && idempotency.expires_at > Time.current

    { error: [ :service_unavailable, "CHECKOUT_BUSY", "Checkout sedang sibuk. Ulangi request dengan Idempotency-Key yang sama." ] }
  rescue ActiveRecord::StatementTimeout => error
    raise unless sqlite_busy_error?(error)

    { error: [ :service_unavailable, "CHECKOUT_BUSY", "Checkout sedang sibuk. Ulangi request dengan Idempotency-Key yang sama." ] }
  end

  def sqlite_busy_error?(error)
    error.cause.is_a?(SQLite3::BusyException)
  end

  def render_outcome(outcome)
    if outcome[:error]
      status, code, message, details = outcome[:error]
      render_error(status, code, message, details || {})
    else
      render json: outcome[:body], status: outcome[:status]
    end
  end

  def serialize_order(order)
    { id: order.id, order_number: order.order_number, status: order.status, subtotal: order.subtotal, shipping_cost: order.shipping_cost, total_amount: order.total_amount, payment_deadline_at: order.payment_deadline_at.iso8601, shipping_method: { id: order.shipping_method.id, name: order.shipping_method.name, cost: order.shipping_method.cost }, items: order.order_items.map { |item| { id: item.id, product_name: item.product_name_snapshot, sku: item.sku_snapshot, unit_price: item.unit_price, quantity: item.quantity, subtotal: item.subtotal } } }
  end
end
