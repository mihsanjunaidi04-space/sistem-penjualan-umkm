require 'rails_helper'
require 'timeout'

RSpec.describe CheckoutService do
  def checkout_records(suffix: SecureRandom.hex(5), shipping_cost: 1_500)
    category = Category.create!(name: "Checkout #{suffix}", slug: "checkout-#{suffix}")
    product = Product.create!(category: category, name: "Product #{suffix}", slug: "product-#{suffix}", sku: "CS-#{suffix}", price: 10_000, stock_on_hand: 3, reserved_stock: 0, is_active: true)
    shipping_method = ShippingMethod.create!(name: "Shipping #{suffix}", estimated_days: 2, cost: shipping_cost, is_active: true)
    user = User.create!(name: "Customer #{suffix}", email: "customer-#{suffix}@example.com", password: 'password123', role: 'customer')
    address = Address.create!(user: user, recipient_name: 'Recipient', phone: '08123456789', address_line: 'Jalan Test', province: 'Jawa Barat', city: 'Bandung', district: 'Coblong', postal_code: '40132')
    cart = Cart.create!(user: user)
    CartItem.create!(cart: cart, product: product, quantity: 1)
    [ user, product, shipping_method, address ]
  end

  def checkout_with_admin_shipping_update(user:, address:, shipping_method:, attributes:)
    admin_lock_acquired = Queue.new
    checkout_busy = Queue.new
    allow_admin_commit = Queue.new
    admin_committed = Queue.new
    admin_errors = Queue.new
    connection_identities = Queue.new
    checkout_outcomes = Queue.new
    admin_signaled_lock = false

    admin_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection_identities << [ :admin, connection.object_id, connection.raw_connection.object_id ]
        ActiveRecord::Base.transaction do
          ShippingMethod.find(shipping_method.id).update!(attributes)
          admin_signaled_lock = true
          admin_lock_acquired << :locked
          allow_admin_commit.pop
        end
        admin_committed << :committed
      end
    rescue StandardError => error
      admin_lock_acquired << error unless admin_signaled_lock
      admin_errors << error
      admin_committed << :failed
    end

    checkout_thread = nil
    begin
      admin_state = Timeout.timeout(10) { admin_lock_acquired.pop }
      raise admin_state if admin_state.is_a?(Exception)

      checkout_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection_identities << [ :checkout, connection.object_id, connection.raw_connection.object_id ]
          raw_connection = connection.raw_connection
          first_busy_attempt = true
          raw_connection.busy_handler do |_retry_count|
            if first_busy_attempt
              first_busy_attempt = false
              checkout_busy << :blocked_on_admin_writer
              admin_committed.pop == :committed
            else
              true
            end
          end

          begin
            checkout_outcomes << CheckoutService.call(user: user, shipping_method_id: shipping_method.id, address_id: address.id)
          ensure
            raw_connection.busy_timeout = 5_000
          end
        end
      rescue StandardError => error
        checkout_outcomes << error
      end

      checkout_state = Timeout.timeout(10) { checkout_busy.pop }
      expect(checkout_state).to eq(:blocked_on_admin_writer)
      identities = 2.times.map { Timeout.timeout(10) { connection_identities.pop } }.to_h { |role, adapter_id, raw_id| [ role, [ adapter_id, raw_id ] ] }
      expect(identities.fetch(:admin)).not_to eq(identities.fetch(:checkout))

      allow_admin_commit << true
      admin_thread.join
      checkout_thread.join
      admin_error = admin_errors.pop unless admin_errors.empty?
      raise admin_error if admin_error

      checkout_outcome = checkout_outcomes.pop
      raise checkout_outcome if checkout_outcome.is_a?(Exception)

      checkout_outcome
    ensure
      allow_admin_commit << true if admin_thread&.alive?
      admin_committed << :committed if checkout_thread&.alive? && !admin_thread&.alive?
      admin_thread&.join
      checkout_thread&.join
    end
  end

  uses_transaction 'uses the latest shipping cost after an admin writer transaction commits'
  it 'uses the latest shipping cost after an admin writer transaction commits' do
    user, product, shipping_method, address = checkout_records

    outcome = checkout_with_admin_shipping_update(user:, address:, shipping_method:, attributes: { cost: 4_200 })

    expect(outcome).to be_a(Order)
    expect(outcome.shipping_cost).to eq(4_200)
    expect(outcome.total_amount).to eq(outcome.subtotal + 4_200)
    expect(product.reload.reserved_stock).to eq(1)
  ensure
    cleanup_checkout_records(user, product, shipping_method)
  end

  uses_transaction 'rejects a shipping method disabled by an admin writer transaction before checkout proceeds'
  it 'rejects a shipping method disabled by an admin writer transaction before checkout proceeds' do
    user, product, shipping_method, address = checkout_records

    expect do
      checkout_with_admin_shipping_update(user:, address:, shipping_method:, attributes: { is_active: false })
    end.to raise_error(CheckoutService::Error) { |error| expect(error.code).to eq('SHIPPING_METHOD_INVALID') }
    expect(Order.where(user: user)).to be_empty
    expect(Payment.joins(:order).where(orders: { user_id: user.id })).to be_empty
    expect(product.reload.reserved_stock).to eq(0)
  ensure
    cleanup_checkout_records(user, product, shipping_method)
  end

  def cleanup_checkout_records(user, product, shipping_method)
    return unless user && product && shipping_method

    order_ids = Order.where(user_id: user.id).pluck(:id)
    InventoryMovement.where(order_id: order_ids).delete_all
    InventoryReservation.where(order_id: order_ids).delete_all
    OrderItem.where(order_id: order_ids).delete_all
    Payment.where(order_id: order_ids).delete_all
    Order.where(id: order_ids).delete_all
    CartItem.where(cart_id: Cart.where(user_id: user.id).select(:id)).delete_all
    Cart.where(user_id: user.id).delete_all
    Address.where(user_id: user.id).delete_all
    Product.where(id: product.id).delete_all
    Category.where(id: product.category_id).delete_all
    ShippingMethod.where(id: shipping_method.id).delete_all
    User.where(id: user.id).delete_all
  end

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
      [ user, address ]
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
