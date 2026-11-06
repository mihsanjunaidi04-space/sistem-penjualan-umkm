require 'rails_helper'

RSpec.describe 'M8 order, cancellation, and shipping API', type: :request do
  def user(role: 'customer', suffix: SecureRandom.hex(4))
    User.create!(name: "M8 User #{suffix}", email: "m8-#{suffix}@example.com", password: 'password123', role: role)
  end

  def headers(record)
    { 'Authorization' => "Bearer #{JwtService.encode({ user_id: record.id, role: record.role })}" }
  end

  def order_for(customer, payment_status: 'pending')
    category = Category.create!(name: "M8 Cat #{SecureRandom.hex(3)}", slug: "m8-cat-#{SecureRandom.hex(3)}")
    product = Product.create!(category: category, name: 'M8 product', slug: "m8-product-#{SecureRandom.hex(3)}", sku: "M8-#{SecureRandom.hex(3)}", price: 50_000, stock_on_hand: 3, reserved_stock: 1, is_active: true)
    method = ShippingMethod.create!(name: "M8 ship #{SecureRandom.hex(3)}", estimated_days: 2, cost: 0, is_active: true)
    order = Order.create!(order_number: "M8-#{SecureRandom.hex(5)}", user: customer, shipping_method: method, status: payment_status == 'paid' ? 'processing' : 'awaiting_payment', subtotal: 50_000, shipping_cost: 0, total_amount: 50_000, recipient_name_snapshot: 'Penerima M8', recipient_phone_snapshot: '0800000000', shipping_address_snapshot: 'Alamat M8', payment_deadline_at: 12.hours.from_now)
    OrderItem.create!(order: order, product: product, product_name_snapshot: product.name, sku_snapshot: product.sku, unit_price: 50_000, quantity: 1, subtotal: 50_000)
    InventoryReservation.create!(order: order, product: product, quantity: 1, status: payment_status == 'paid' ? 'converted' : 'reserved', expires_at: order.payment_deadline_at, converted_at: payment_status == 'paid' ? Time.current : nil)
    payment = Payment.create!(order: order, payment_method: 'manual_transfer', amount: 50_000, status: payment_status)
    [order, product, payment]
  end

  it 'keeps customer ownership and returns shipment/cancellation data' do
    owner = user
    other = user
    order, = order_for(owner)
    get "/customer/orders/#{order.id}", headers: headers(other)
    expect(response).to have_http_status(:not_found)
    get "/customer/orders/#{order.id}", headers: headers(owner)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig('data', 'order', 'shipment')).to be_nil
    expect(JSON.parse(response.body).dig('data', 'order', 'cancellation_requests')).to eq([])
  end

  it 'submits cancellation, blocks payment approval, and releases reservation atomically when approved' do
    customer = user
    admin = user(role: 'admin')
    order, product, payment = order_for(customer)
    proof = PaymentProof.create!(payment: payment, storage_key: 'test-proof', original_filename: 'proof.png', mime_type: 'image/png', file_size: 10, uploaded_at: Time.current, status: 'submitted')
    payment.update!(status: 'waiting_verification')
    post "/customer/orders/#{order.id}/cancellation-requests", params: { reason: 'Salah alamat' }, headers: headers(customer), as: :json
    expect(response).to have_http_status(:created)
    cancellation_id = JSON.parse(response.body).dig('data', 'cancellation_request', 'id')
    post "/admin/payments/#{payment.id}/approve", headers: headers(admin)
    expect(response).to have_http_status(:unprocessable_content)
    expect(payment.reload.status).to eq('waiting_verification')
    post "/admin/cancellation-requests/#{cancellation_id}/approve", headers: headers(admin)
    expect(response).to have_http_status(:ok)
    expect(order.reload.status).to eq('cancelled')
    expect(payment.reload.status).to eq('rejected')
    expect(proof.reload.status).to eq('rejected')
    expect(product.reload.reserved_stock).to eq(0)
    expect(order.inventory_reservations.first.reload.status).to eq('released')
    expect(InventoryMovement.where(order: order, movement_type: 'reservation_release').count).to eq(1)
  end

  it 'allows rejected cancellation to continue payment and prevents duplicate active requests' do
    customer = user
    admin = user(role: 'admin')
    order, = order_for(customer)
    post "/customer/orders/#{order.id}/cancellation-requests", params: { reason: 'Berubah pikiran' }, headers: headers(customer), as: :json
    cancellation_id = JSON.parse(response.body).dig('data', 'cancellation_request', 'id')
    post "/customer/orders/#{order.id}/cancellation-requests", params: { reason: 'Kirim ulang' }, headers: headers(customer), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    post "/admin/cancellation-requests/#{cancellation_id}/reject", params: { admin_note: 'Pesanan tetap diproses sesuai kebijakan.' }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(order.reload.status).to eq('awaiting_payment')
  end

  it 'manages one shipment through valid transitions and keeps order shipped after delivery' do
    admin = user(role: 'admin')
    order, = order_for(user, payment_status: 'paid')
    post "/admin/orders/#{order.id}/shipments", headers: headers(admin)
    expect(response).to have_http_status(:created)
    shipment_id = JSON.parse(response.body).dig('data', 'shipment', 'id')
    post "/admin/orders/#{order.id}/shipments", headers: headers(admin)
    expect(response).to have_http_status(:unprocessable_content)
    patch "/admin/shipments/#{shipment_id}/pack", headers: headers(admin)
    expect(response).to have_http_status(:ok)
    patch "/admin/shipments/#{shipment_id}/ship", params: { tracking_number: '' }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    patch "/admin/shipments/#{shipment_id}/ship", params: { tracking_number: 'RESI-M8-001' }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    patch "/admin/shipments/#{shipment_id}/deliver", headers: headers(admin)
    expect(response).to have_http_status(:ok)
    expect(order.reload.status).to eq('shipped')
    expect(order.shipment.reload.status).to eq('delivered')
    expect(order.shipment.tracking_number).to eq('RESI-M8-001')
  end

  it 'auto-completes only eligible shipped orders and is idempotent' do
    order, = order_for(user, payment_status: 'paid')
    order.update!(status: 'shipped', shipped_at: 8.days.ago)
    now = Time.current
    OrderCompletionService.call(now: now)
    OrderCompletionService.call(now: now)
    expect(order.reload.status).to eq('completed')
    expect(order.completed_at).to be_present
    expect(AuditLog.where(action: 'order_completed', resource_id: order.id.to_s).count).to eq(1)
  end

  it 'rolls back cancellation when reservation data is inconsistent' do
    customer = user
    admin = user(role: 'admin')
    order, product, = order_for(customer)
    post "/customer/orders/#{order.id}/cancellation-requests", params: { reason: 'Tes rollback' }, headers: headers(customer), as: :json
    cancellation_id = JSON.parse(response.body).dig('data', 'cancellation_request', 'id')
    product.update!(reserved_stock: 0)
    post "/admin/cancellation-requests/#{cancellation_id}/approve", headers: headers(admin)
    expect(response).to have_http_status(:unprocessable_content)
    expect(order.reload.status).to eq('awaiting_payment')
    expect(order.cancellation_requests.first.reload.status).to eq('pending')
    expect(InventoryMovement.where(order: order, movement_type: 'reservation_release')).to be_empty
  end
end
