require 'rails_helper'

RSpec.describe Refund, type: :model do
  def user(role: 'customer')
    suffix = SecureRandom.hex(4)
    User.create!(name: "Refund Model #{suffix}", email: "refund-model-#{suffix}@example.com", password: 'password123', role: role)
  end

  def order_for(customer)
    category = Category.create!(name: "Refund Model Cat #{SecureRandom.hex(3)}", slug: "refund-model-cat-#{SecureRandom.hex(3)}")
    method = ShippingMethod.create!(name: "Refund Model Ship #{SecureRandom.hex(3)}", estimated_days: 2, cost: 0, is_active: true)
    Order.create!(order_number: "RM-#{SecureRandom.hex(5)}", user: customer, shipping_method: method, status: 'processing', subtotal: 100, shipping_cost: 0, total_amount: 100, payment_deadline_at: 12.hours.from_now)
  end

  it 'rejects a refund whose order does not belong to its payment' do
    payment_order = order_for(user)
    other_order = order_for(user)
    payment = Payment.create!(order: payment_order, payment_method: 'manual_transfer', amount: 100, status: 'paid')
    refund = described_class.new(payment: payment, order: other_order, amount: 50, reason: 'Test', status: 'pending')

    expect(refund).not_to be_valid
    expect(refund.errors[:order]).to be_present
  end

  it 'requires processing metadata and an admin processor for processed status' do
    order = order_for(user)
    payment = Payment.create!(order: order, payment_method: 'manual_transfer', amount: 100, status: 'paid')
    refund = described_class.new(payment: payment, order: order, amount: 100, reason: 'Test', status: 'processed', reference_number: 'BANK-1', processed_at: Time.current, processed_by: user)

    expect(refund).not_to be_valid
    expect(refund.errors[:processed_by]).to be_present
  end
end
