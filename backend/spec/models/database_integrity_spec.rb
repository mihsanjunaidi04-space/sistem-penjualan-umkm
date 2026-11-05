# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'database integrity', type: :model do
  it 'keeps auth_sessions out of M2 and uses WAL with busy timeout configured' do
    expect(ActiveRecord::Base.connection.data_source_exists?(:auth_sessions)).to be(false)
    expect(ActiveRecord::Base.connection.select_value('PRAGMA journal_mode').to_s.downcase).to eq('wal')
    expect(ActiveRecord::Base.connection.select_value('PRAGMA busy_timeout').to_i).to eq(5000)
  end

  it 'enforces critical uniqueness and validation constraints' do
    category = Category.create!(name: 'Elektronik Unique', slug: 'elektronik-unique')
    product = Product.create!(category: category, name: 'Keyboard', slug: 'keyboard-unique', sku: 'KB-001-UNIQUE', price: 150_000, stock_on_hand: 10, reserved_stock: 2)

    User.create!(name: 'Alice', email: 'alice@example.com', password: 'password123', role: 'customer')
    expect { User.create!(name: 'Alice Duplicate', email: 'alice@example.com', password: 'password123', role: 'customer') }.to raise_error(ActiveRecord::RecordInvalid)
    expect { Product.create!(category: category, name: 'Bad', slug: 'bad-product-unique', sku: 'KB-002-UNIQUE', price: -1, stock_on_hand: 5, reserved_stock: 0) }.to raise_error(ActiveRecord::RecordInvalid)

    user = User.create!(name: 'Bob', email: 'bob@example.com', password: 'password123', role: 'customer')
    cart = Cart.create!(user: user)
    expect { CartItem.create!(cart: cart, product: product, quantity: 0) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'enforces foreign key protection for order items at the database layer' do
    user = User.create!(name: 'Charlie', email: 'charlie-unique@example.com', password: 'password123', role: 'customer')
    shipping_method = ShippingMethod.create!(name: 'Reguler Unique', description: 'Standard', estimated_days: 3, cost: 15_000)
    category = Category.create!(name: 'Gadget Unique', slug: 'gadget-unique')
    product = Product.create!(category: category, name: 'Mouse', slug: 'mouse-unique', sku: 'MS-001-UNIQUE', price: 80_000, stock_on_hand: 10, reserved_stock: 0)
    order = Order.create!(order_number: 'ORD-1001-UNIQUE', user: user, shipping_method: shipping_method, payment_deadline_at: 1.day.from_now, status: 'awaiting_payment', subtotal: 100_000, discount_amount: 0, shipping_cost: 15_000, total_amount: 115_000)

    expect do
      OrderItem.new(order_id: 9_999_999, product: product, product_name_snapshot: 'Mouse', sku_snapshot: 'MS-001', unit_price: 80_000, quantity: 1, subtotal: 80_000).save!(validate: false)
    end.to raise_error(ActiveRecord::StatementInvalid)

    expect(order.reload).to be_present
  end
end
