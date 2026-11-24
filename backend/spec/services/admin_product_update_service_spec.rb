require 'rails_helper'

RSpec.describe AdminProductUpdateService do
  def product_and_admin
    suffix = SecureRandom.hex(5)
    category = Category.create!(name: "Admin stock #{suffix}", slug: "admin-stock-#{suffix}")
    product = Product.create!(category:, name: "Product #{suffix}", slug: "product-#{suffix}", sku: "ST-#{suffix}", price: 100, stock_on_hand: 5, reserved_stock: 1)
    admin = User.create!(name: 'Inventory Admin', email: "inventory-admin-#{suffix}@example.com", password: 'password123', role: 'admin')
    [ product, admin ]
  end

  it 'rolls back the stock update when movement creation fails' do
    product, admin = product_and_admin
    allow(InventoryMovement).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'movement insert failed')

    expect {
      described_class.call(product:, attributes: { stock_on_hand: 8 }, admin:)
    }.to raise_error(ActiveRecord::StatementInvalid, 'movement insert failed')

    expect(product.reload).to have_attributes(stock_on_hand: 5, reserved_stock: 1)
    expect(product.inventory_movements).to be_empty
  end

  it 'serializes an admin stock reduction against checkout reservation' do
    suffix = SecureRandom.hex(5)
    category = Category.create!(name: "Stock race #{suffix}", slug: "stock-race-#{suffix}")
    product = Product.create!(category:, name: "Race Product #{suffix}", slug: "race-product-#{suffix}", sku: "RC-#{suffix}", price: 100, stock_on_hand: 1, reserved_stock: 0, is_active: true)
    admin = User.create!(name: 'Race Admin', email: "race-admin-#{suffix}@example.com", password: 'password123', role: 'admin')
    customer = User.create!(name: 'Race Customer', email: "race-customer-#{suffix}@example.com", password: 'password123', role: 'customer')
    address = Address.create!(user: customer, recipient_name: 'Race Customer', phone: '08123456789', address_line: 'Jalan Race', province: 'Jawa Barat', city: 'Bandung', district: 'Coblong', postal_code: '40132')
    shipping_method = ShippingMethod.create!(name: "Race Shipping #{suffix}", estimated_days: 1, cost: 0, is_active: true)
    cart = Cart.create!(user: customer)
    CartItem.create!(cart:, product:, quantity: 1)
    ready = Queue.new
    start = Queue.new
    results = Queue.new

    operations = [
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          result = begin
            described_class.call(product: Product.find(product.id), attributes: { stock_on_hand: 0 }, admin:)
          rescue StandardError => error
            error
          end
          results << [ :adjustment, result ]
        end
      end,
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          result = begin
            CheckoutService.call(user: customer, shipping_method_id: shipping_method.id, address_id: address.id)
          rescue StandardError => error
            error
          end
          results << [ :checkout, result ]
        end
      end
    ]
    2.times { ready.pop }
    2.times { start << true }
    operations.each(&:join)
    outcomes = 2.times.to_h { results.pop }

    expect(product.reload.reserved_stock).to be_between(0, product.stock_on_hand)
    adjustment_succeeded = outcomes[:adjustment].is_a?(Product)
    checkout_succeeded = outcomes[:checkout].is_a?(Order)
    expect([ adjustment_succeeded, checkout_succeeded ]).to satisfy { |values| values == [ true, false ] || values == [ false, true ] }
    if adjustment_succeeded
      expect(product.reload).to have_attributes(stock_on_hand: 0, reserved_stock: 0)
      expect(product.inventory_movements.order(:id).last).to have_attributes(quantity: -1, stock_before: 1, stock_after: 0)
    else
      expect(product.reload).to have_attributes(stock_on_hand: 1, reserved_stock: 1)
      expect(product.inventory_movements.pluck(:movement_type)).to eq([ 'reservation' ])
      expect(product.inventory_movements.where(created_by: admin)).to be_empty
    end
  ensure
    operations&.each(&:join)
  end
end
