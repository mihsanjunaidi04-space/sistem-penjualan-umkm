require 'rails_helper'

RSpec.describe RefundService do
  def user(role: 'customer')
    suffix = SecureRandom.hex(4)
    User.create!(name: "Refund Service #{suffix}", email: "refund-service-#{suffix}@example.com", password: 'password123', role: role)
  end

  def paid_payment(amount: 100_000)
    customer = user
    category = Category.create!(name: "Refund Service Cat #{SecureRandom.hex(3)}", slug: "refund-service-cat-#{SecureRandom.hex(3)}")
    method = ShippingMethod.create!(name: "Refund Service Ship #{SecureRandom.hex(3)}", estimated_days: 2, cost: 0, is_active: true)
    order = Order.create!(order_number: "RS-#{SecureRandom.hex(5)}", user: customer, shipping_method: method, status: 'processing', subtotal: amount, shipping_cost: 0, total_amount: amount, payment_deadline_at: 12.hours.from_now)
    Payment.create!(order: order, payment_method: 'manual_transfer', amount: amount, status: 'paid')
  end

  let(:request) { instance_double(ActionDispatch::Request, remote_ip: '192.0.2.1', user_agent: 'RefundServiceSpec') }

  it 'creates a pending refund and records its actor in the audit log' do
    payment = paid_payment
    admin = user(role: 'admin')

    refund = described_class.create!(payment_id: payment.id, idempotency_key: SecureRandom.uuid, amount: 25_000, reason: 'Refund parsial', admin: admin, request: request)

    expect(refund).to have_attributes(status: 'pending', amount: 25_000, payment_id: payment.id, order_id: payment.order_id)
    expect(AuditLog.where(user: admin, action: 'refund_created', resource_id: refund.id.to_s)).to exist
  end

  it 'does not allow service use by a non-admin' do
    payment = paid_payment

    expect {
      described_class.create!(payment_id: payment.id, idempotency_key: SecureRandom.uuid, amount: 25_000, reason: 'Refund parsial', admin: user, request: request)
    }.to raise_error(RefundService::Error, 'Refund hanya dapat dikelola admin.')
    expect(Refund.where(payment: payment)).to be_empty
  end

  it 'rolls back refund creation when the audit log fails' do
    payment = paid_payment
    admin = user(role: 'admin')
    allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'audit write failed')

    expect {
      described_class.create!(payment_id: payment.id, idempotency_key: SecureRandom.uuid, amount: 25_000, reason: 'Refund parsial', admin: admin, request: request)
    }.to raise_error(ActiveRecord::StatementInvalid, 'audit write failed')

    expect(Refund.where(payment: payment)).to be_empty
  end
end
