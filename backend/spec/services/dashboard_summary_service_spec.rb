require "rails_helper"

RSpec.describe DashboardSummaryService do
  def user(role: "customer")
    suffix = SecureRandom.hex(5)
    User.create!(name: "Dashboard #{suffix}", email: "dashboard-#{suffix}@example.com", password: "password123", role:)
  end

  def product(name:, stock:, reserved:)
    category = Category.create!(name: "Category #{SecureRandom.hex(4)}", slug: "category-#{SecureRandom.hex(4)}")
    Product.create!(category:, name:, slug: "#{name.parameterize}-#{SecureRandom.hex(4)}", sku: "SKU-#{SecureRandom.hex(4)}", price: 100, stock_on_hand: stock, reserved_stock: reserved, is_active: true)
  end

  def order_with_payment(customer:, verified_at:, payment_status:, amount:, created_at: Time.utc(2026, 2, 28, 17))
    shipping_method = ShippingMethod.create!(name: "Ship #{SecureRandom.hex(4)}", estimated_days: 2, cost: 50, is_active: true)
    order = Order.create!(order_number: "DASH-#{SecureRandom.hex(5)}", user: customer, shipping_method:, status: "processing", subtotal: amount - 50, shipping_cost: 50, total_amount: amount, payment_deadline_at: created_at + 12.hours, created_at:)
    payment = Payment.create!(order:, payment_method: "manual_transfer", amount:, status: payment_status, verified_at:)
    [ order, payment ]
  end

  let(:period) { ReportingPeriod.new(from: "2026-03-01", to: "2026-03-01") }

  it "counts verified payments and processed refunds without multiplying item totals" do
    admin = user(role: "admin")
    customer = user
    sold_product = product(name: "Sold Product", stock: 20, reserved: 5)
    order, payment = order_with_payment(customer:, created_at: Time.utc(2026, 2, 28, 16), verified_at: Time.utc(2026, 2, 28, 16), payment_status: "paid", amount: 1_050)
    OrderItem.create!(order:, product: sold_product, product_name_snapshot: "Sold Product", sku_snapshot: sold_product.sku, unit_price: 100, quantity: 2, subtotal: 200)
    OrderItem.create!(order:, product: sold_product, product_name_snapshot: "Sold Product", sku_snapshot: sold_product.sku, unit_price: 100, quantity: 3, subtotal: 300)
    Refund.create!(payment:, order:, amount: 200, reason: "partial", status: "processed", processed_by: admin, processed_at: Time.utc(2026, 2, 28, 17), reference_number: "REF-1")
    Refund.create!(payment:, order:, amount: 50, reason: "processed at exclusive end", status: "processed", processed_by: admin, processed_at: Time.utc(2026, 3, 1, 16), reference_number: "REF-2")
    Refund.create!(payment:, order:, amount: 100, reason: "pending", status: "pending")
    Refund.create!(payment:, order:, amount: 100, reason: "rejected", status: "rejected", notes: "Rejected")

    result = described_class.call(period:)

    expect(result.dig(:summary, :verified_payments)).to eq(count: 1, amount: 1_050)
    expect(result.dig(:summary, :processed_refunds)).to eq(count: 1, amount: 200)
    expect(result.dig(:summary, :net_receipts)).to eq(850)
    expect(result.dig(:summary, :orders_created)).to eq(1)
    expect(result.dig(:summary, :products_sold)).to eq(quantity: 5, gross_subtotal: 500)
    expect(result.dig(:summary, :inventory)).to eq(stock_on_hand: Product.sum(:stock_on_hand), reserved_stock: Product.sum(:reserved_stock), available_stock: Product.sum(:stock_on_hand) - Product.sum(:reserved_stock))
  end

  it "includes refunded payments, excludes rejected or unverified payments, and counts orders by creation date" do
    customer = user
    admin = user(role: "admin")
    sold_product = product(name: "Verified Product", stock: 8, reserved: 2)
    verified_order, full_refund_payment = order_with_payment(customer:, verified_at: Time.utc(2026, 3, 1, 15), payment_status: "refunded", amount: 700)
    Refund.create!(payment: full_refund_payment, order: verified_order, amount: 700, reason: "full refund", status: "processed", processed_by: admin, processed_at: Time.utc(2026, 3, 1, 15), reference_number: "REF-FULL")
    OrderItem.create!(order: verified_order, product: sold_product, product_name_snapshot: "Verified Product", sku_snapshot: sold_product.sku, unit_price: 200, quantity: 2, subtotal: 400)
    rejected_order, rejected_payment = order_with_payment(customer:, verified_at: Time.utc(2026, 3, 1, 14), payment_status: "rejected", amount: 900)
    OrderItem.create!(order: rejected_order, product: sold_product, product_name_snapshot: "Verified Product", sku_snapshot: sold_product.sku, unit_price: 200, quantity: 10, subtotal: 2_000)
    OrderItem.create!(order: order_with_payment(customer:, verified_at: nil, payment_status: "pending", amount: 500).first, product: sold_product, product_name_snapshot: "Verified Product", sku_snapshot: sold_product.sku, unit_price: 200, quantity: 4, subtotal: 800)
    outside_order, = order_with_payment(customer:, created_at: Time.utc(2026, 3, 1, 16), verified_at: Time.utc(2026, 3, 1, 16), payment_status: "paid", amount: 1_200)
    OrderItem.create!(order: outside_order, product: sold_product, product_name_snapshot: "Verified Product", sku_snapshot: sold_product.sku, unit_price: 200, quantity: 6, subtotal: 1_200)

    result = described_class.call(period:)

    expect(result.dig(:summary, :orders_created)).to eq(3)
    expect(result.dig(:summary, :verified_payments)).to eq(count: 1, amount: 700)
    expect(result.dig(:summary, :processed_refunds)).to eq(count: 1, amount: 700)
    expect(result.dig(:summary, :net_receipts)).to eq(0)
    expect(result.dig(:summary, :products_sold)).to eq(quantity: 2, gross_subtotal: 400)
    expect(rejected_payment.status).to eq("rejected")
  end

  it "returns zeroes for empty activity and inventory" do
    result = described_class.call(period:)

    expect(result.dig(:summary, :orders_created)).to eq(0)
    expect(result.dig(:summary, :verified_payments)).to eq(count: 0, amount: 0)
    expect(result.dig(:summary, :processed_refunds)).to eq(count: 0, amount: 0)
    expect(result.dig(:summary, :net_receipts)).to eq(0)
    expect(result.dig(:summary, :products_sold)).to eq(quantity: 0, gross_subtotal: 0)
    stock_on_hand = Product.sum(:stock_on_hand)
    reserved_stock = Product.sum(:reserved_stock)
    expect(result.dig(:summary, :inventory)).to eq(stock_on_hand:, reserved_stock:, available_stock: stock_on_hand - reserved_stock)
  end
end
