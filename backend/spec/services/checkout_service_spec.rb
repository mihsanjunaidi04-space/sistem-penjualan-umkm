require 'rails_helper'

RSpec.describe CheckoutService do
  it 'allows only one of two concurrent checkouts to reserve the last unit' do
    suffix = SecureRandom.hex(5)
    category = Category.create!(name: "Concurrency #{suffix}", slug: "concurrency-#{suffix}")
    product = Product.create!(category: category, name: "Concurrent Product #{suffix}", slug: "concurrent-product-#{suffix}", sku: "CC-#{suffix}", price: 10_000, stock_on_hand: 1, reserved_stock: 0, is_active: true)
    shipping_method = ShippingMethod.create!(name: "Concurrent Shipping #{suffix}", estimated_days: 1, cost: 0, is_active: true)
    users = 2.times.map do |index|
      user = User.create!(name: "Concurrent User #{suffix}-#{index}", email: "concurrent-#{suffix}-#{index}@example.com", password: 'password123', role: 'customer')
      address = Address.create!(user: user, recipient_name: 'Concurrent Recipient', phone: '08123456789', address_line: 'Jalan Concurrent', province: 'Jawa Barat', city: 'Bandung', district: 'Coblong', postal_code: '40132')
      cart = Cart.create!(user: user)
      CartItem.create!(cart: cart, product: product, quantity: 1)
      [user, address]
    end

    results = Queue.new
    threads = users.map do |user, address|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            results << CheckoutService.call(user: user, shipping_method_id: shipping_method.id, address_id: address.id)
          rescue StandardError => error
            results << error
          end
        end
      end
    end
    threads.each(&:join)

    outcomes = 2.times.map { results.pop }
    expect(outcomes.count { |outcome| outcome.is_a?(Order) }).to eq(1)
    expect(outcomes.count { |outcome| outcome.is_a?(CheckoutService::Error) }).to eq(1)
    expect(product.reload.reserved_stock).to eq(1)
  ensure
    threads&.each(&:join)
  end
end
