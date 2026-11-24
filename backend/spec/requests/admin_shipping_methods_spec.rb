require 'rails_helper'

RSpec.describe 'Admin shipping methods API', type: :request do
  def user(role: 'customer')
    suffix = SecureRandom.hex(4)
    User.create!(name: "Shipping User #{suffix}", email: "shipping-#{suffix}@example.com", password: 'password123', role: role)
  end

  def headers(record)
    { 'Authorization' => "Bearer #{JwtService.encode({ user_id: record.id, role: record.role })}" }
  end

  def shipping_method(attributes = {})
    ShippingMethod.create!({ name: "Shipping #{SecureRandom.hex(4)}", description: 'Metode uji', estimated_days: 3, cost: 12_000, is_active: true }.merge(attributes))
  end

  def order_for(method)
    customer = user
    Order.create!(
      order_number: "SHIP-#{SecureRandom.hex(5)}",
      user: customer,
      shipping_method: method,
      status: 'awaiting_payment',
      subtotal: 20_000,
      shipping_cost: 12_000,
      total_amount: 32_000,
      payment_deadline_at: 12.hours.from_now
    )
  end

  it 'allows admins to list, create, and update methods while recording audit events' do
    admin = user(role: 'admin')
    active_method = shipping_method(name: 'Aktif Shipping')
    inactive_method = shipping_method(name: 'Nonaktif Shipping', is_active: false)

    get '/admin/shipping-methods', headers: headers(admin)
    expect(response).to have_http_status(:ok)
    listed_ids = JSON.parse(response.body).dig('data', 'shipping_methods').pluck('id')
    expect(listed_ids).to include(active_method.id, inactive_method.id)

    post '/admin/shipping-methods', params: { name: 'Kilat', description: 'Pengiriman cepat', estimated_days: 1, cost: 30_000, is_active: true, id: 999_999, user_id: 999_999 }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:created)
    created_id = JSON.parse(response.body).dig('data', 'shipping_method', 'id')
    created = ShippingMethod.find(created_id)
    expect(created).to have_attributes(name: 'Kilat', description: 'Pengiriman cepat', estimated_days: 1, cost: 30_000, is_active: true)
    expect(created.id).not_to eq(999_999)
    created_at = created.created_at
    expect(AuditLog.where(user: admin, action: 'shipping_method_created', resource_id: created.id.to_s)).to exist

    patch "/admin/shipping-methods/#{created.id}", params: { cost: 35_000, is_active: false, id: 999_999, created_at: 10.years.ago }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(created.reload).to have_attributes(cost: 35_000, is_active: false)
    expect(created.created_at).to eq(created_at)
    expect(AuditLog.where(user: admin, action: 'shipping_method_updated', resource_id: created.id.to_s)).to exist
  end

  it 'requires an admin for each admin endpoint' do
    admin = user(role: 'admin')
    customer = user
    method = shipping_method

    [ nil, customer ].each do |actor|
      request_headers = actor ? headers(actor) : {}

      get '/admin/shipping-methods', headers: request_headers
      expect(response).to have_http_status(actor ? :forbidden : :unauthorized)
      post '/admin/shipping-methods', params: { name: 'Unauthorized', estimated_days: 1, cost: 0 }, headers: request_headers, as: :json
      expect(response).to have_http_status(actor ? :forbidden : :unauthorized)
      patch "/admin/shipping-methods/#{method.id}", params: { cost: 1 }, headers: request_headers, as: :json
      expect(response).to have_http_status(actor ? :forbidden : :unauthorized)
    end

    expect(admin.admin?).to be(true)
    expect(method.reload.cost).to eq(12_000)
  end

  it 'keeps the customer endpoint limited to active methods' do
    customer = user
    active_method = shipping_method(name: 'Public Active')
    shipping_method(name: 'Public Inactive', is_active: false)

    get '/shipping-methods', headers: headers(customer)

    expect(response).to have_http_status(:ok)
    methods = JSON.parse(response.body).dig('data', 'shipping_methods')
    expect(methods.pluck('id')).to include(active_method.id)
    expect(methods.pluck('name')).not_to include('Public Inactive')
    expect(methods.first).not_to have_key('is_active')
  end

  it 'rejects duplicate names, nonpositive estimates, and negative costs' do
    admin = user(role: 'admin')
    existing = shipping_method(name: 'Unique Shipping')

    post '/admin/shipping-methods', params: { name: existing.name, estimated_days: 1, cost: 0 }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).dig('error', 'details')).to have_key('name')

    post '/admin/shipping-methods', params: { name: 'Zero Days', estimated_days: 0, cost: 0 }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).dig('error', 'details')).to have_key('estimated_days')

    post '/admin/shipping-methods', params: { name: 'Negative Cost', estimated_days: 1, cost: -1 }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).dig('error', 'details')).to have_key('cost')
  end

  it 'does not allow renaming a method used by an order and provides no hard-delete route' do
    admin = user(role: 'admin')
    method = shipping_method(name: 'Historical Method')
    order = order_for(method)

    patch "/admin/shipping-methods/#{method.id}", params: { name: 'Renamed Method' }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).dig('error', 'code')).to eq('SHIPPING_METHOD_NAME_IMMUTABLE')
    expect(method.reload.name).to eq('Historical Method')

    delete "/admin/shipping-methods/#{method.id}", headers: headers(admin)
    expect(response).to have_http_status(:not_found)
    expect(ShippingMethod.exists?(method.id)).to be(true)
    expect(order.reload.shipping_method_id).to eq(method.id)
  end

  it 'does not let an inactive method be used for a new checkout' do
    customer = user
    admin = user(role: 'admin')
    category = Category.create!(name: "Shipping Cat #{SecureRandom.hex(3)}", slug: "shipping-cat-#{SecureRandom.hex(3)}")
    product = Product.create!(category: category, name: 'Shipping Product', slug: "shipping-product-#{SecureRandom.hex(3)}", sku: "SH-#{SecureRandom.hex(3)}", price: 10_000, stock_on_hand: 5, reserved_stock: 0, is_active: true)
    address = Address.create!(user: customer, recipient_name: 'Penerima', phone: '08123456789', address_line: 'Jalan Contoh', province: 'Jawa Barat', city: 'Bandung', district: 'Coblong', postal_code: '40132')
    method = shipping_method(is_active: true)
    Cart.create!(user: customer).cart_items.create!(product: product, quantity: 1)

    patch "/admin/shipping-methods/#{method.id}", params: { is_active: false }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:ok)

    post '/checkout', params: { address_id: address.id, shipping_method_id: method.id }, headers: headers(customer).merge('Idempotency-Key' => SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).dig('error', 'code')).to eq('SHIPPING_METHOD_INVALID')
    expect(Order.where(user: customer)).to be_empty
  end

  it 'preserves historical shipping cost and method name when a method is updated' do
    admin = user(role: 'admin')
    method = shipping_method(name: 'Stored Method')
    order = order_for(method)
    shipment = order.create_shipment!(shipping_method: method, recipient_name_snapshot: 'Penerima', shipping_address_snapshot: 'Alamat', status: 'not_shipped')

    patch "/admin/shipping-methods/#{method.id}", params: { description: 'Deskripsi baru', estimated_days: 5, cost: 20_000, is_active: false }, headers: headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(order.reload).to have_attributes(shipping_cost: 12_000, shipping_method_id: method.id)
    expect(shipment.reload.shipping_method.name).to eq('Stored Method')
    expect(shipment.shipping_method.cost).to eq(20_000)
  end

  it 'rolls back method creation and update when audit logging fails' do
    admin = user(role: 'admin')
    method = shipping_method(name: 'Audit Existing')

    allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'audit write failed')

    expect {
      post '/admin/shipping-methods', params: { name: 'Audit Create Failure', estimated_days: 1, cost: 0 }, headers: headers(admin), as: :json
    }.to raise_error(ActiveRecord::StatementInvalid, 'audit write failed')
    expect(ShippingMethod.exists?(name: 'Audit Create Failure')).to be(false)

    expect {
      patch "/admin/shipping-methods/#{method.id}", params: { cost: 25_000 }, headers: headers(admin), as: :json
    }.to raise_error(ActiveRecord::StatementInvalid, 'audit write failed')
    expect(method.reload.cost).to eq(12_000)
  end
end
