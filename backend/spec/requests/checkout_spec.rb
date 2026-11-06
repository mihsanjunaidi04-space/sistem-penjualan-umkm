require 'rails_helper'

RSpec.describe 'Cart and checkout API', type: :request do
  def user(role: 'customer', suffix: SecureRandom.hex(4))
    User.create!(name: "Checkout User #{suffix}", email: "checkout-#{suffix}@example.com", password: 'password123', role: role)
  end

  def auth_headers(user)
    { 'Authorization' => "Bearer #{JwtService.encode({ user_id: user.id, role: user.role })}" }
  end

  def category_record(suffix = SecureRandom.hex(4))
    Category.create!(name: "Checkout Category #{suffix}", slug: "checkout-category-#{suffix}")
  end

  def product_record(category, attributes = {})
    suffix = SecureRandom.hex(4)
    Product.create!({ category: category, name: "Checkout Product #{suffix}", slug: "checkout-product-#{suffix}", sku: "CO-#{suffix}", price: 10_000, stock_on_hand: 10, reserved_stock: 0, is_active: true }.merge(attributes))
  end

  def address_for(user)
    Address.create!(user: user, recipient_name: 'Penerima', phone: '08123456789', address_line: 'Jalan Contoh 1', province: 'Jawa Barat', city: 'Bandung', district: 'Coblong', postal_code: '40132')
  end

  def shipping_method
    ShippingMethod.find_or_create_by!(name: "Reguler Test #{SecureRandom.hex(3)}") { |method| method.estimated_days = 3; method.cost = 15_000; method.is_active = true }
  end

  def add_to_cart(user, product, quantity)
    post '/cart/items', params: { product_id: product.id, quantity: quantity }, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:created).or have_http_status(:ok)
  end

  describe 'cart' do
    it 'supports add, update, delete, clear, and ownership checks' do
      user_a = user
      user_b = user
      product = product_record(category_record)
      add_to_cart(user_a, product, 2)
      cart_item_id = JSON.parse(response.body).dig('data', 'items', 0, 'id')

      get '/cart', headers: auth_headers(user_b)
      expect(JSON.parse(response.body).dig('data', 'items')).to be_empty

      patch "/cart/items/#{cart_item_id}", params: { quantity: 3 }, headers: auth_headers(user_b), as: :json
      expect(response).to have_http_status(:not_found)

      patch "/cart/items/#{cart_item_id}", params: { quantity: 4 }, headers: auth_headers(user_a), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig('data', 'subtotal')).to eq(40_000)

      delete "/cart/items/#{cart_item_id}", headers: auth_headers(user_a)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig('data', 'items')).to be_empty

      add_to_cart(user_a, product, 1)
      delete '/cart/items', headers: auth_headers(user_a)
      expect(JSON.parse(response.body).dig('data', 'item_count')).to eq(0)
    end

    it 'rejects inactive products and insufficient stock' do
      user_record = user
      inactive = product_record(category_record, is_active: false)
      post '/cart/items', params: { product_id: inactive.id, quantity: 1 }, headers: auth_headers(user_record), as: :json
      expect(response).to have_http_status(:not_found)

      limited = product_record(category_record, stock_on_hand: 2)
      post '/cart/items', params: { product_id: limited.id, quantity: 3 }, headers: auth_headers(user_record), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig('error', 'code')).to eq('STOCK_UNAVAILABLE')
    end
  end

  describe 'checkout' do
    it 'recalculates price, creates snapshots, payment, reservation, and deadline atomically' do
      user_record = user
      product = product_record(category_record, price: 10_000, stock_on_hand: 5)
      address = address_for(user_record)
      method = shipping_method
      add_to_cart(user_record, product, 2)
      product.update!(price: 12_500)

      post '/checkout', params: { address_id: address.id, shipping_method_id: method.id }, headers: auth_headers(user_record).merge('Idempotency-Key' => SecureRandom.uuid), as: :json
      expect(response).to have_http_status(:created)
      order = Order.find(JSON.parse(response.body).dig('data', 'order', 'id'))
      expect(order.subtotal).to eq(25_000)
      expect(order.total_amount).to eq(40_000)
      expect(order.status).to eq('awaiting_payment')
      expect(order.payment_deadline_at).to be_within(5.seconds).of(12.hours.from_now)
      expect(order.payment.status).to eq('pending')
      expect(order.order_items.first.product_name_snapshot).to eq(product.name)
      expect(order.inventory_reservations.first.quantity).to eq(2)
      expect(product.reload.reserved_stock).to eq(2)
      expect(user_record.carts.first.cart_items).to be_empty
    end

    it 'replays the same idempotency key and rejects a changed payload' do
      user_record = user
      product = product_record(category_record)
      address = address_for(user_record)
      method = shipping_method
      add_to_cart(user_record, product, 1)
      key = SecureRandom.uuid
      payload = { address_id: address.id, shipping_method_id: method.id }

      post '/checkout', params: payload, headers: auth_headers(user_record).merge('Idempotency-Key' => key), as: :json
      expect(response).to have_http_status(:created)
      order_count = Order.where(user: user_record).count
      post '/checkout', params: payload, headers: auth_headers(user_record).merge('Idempotency-Key' => key), as: :json
      expect(response).to have_http_status(:created)
      expect(Order.where(user: user_record).count).to eq(order_count)

      post '/checkout', params: payload.merge(customer_notes: 'changed'), headers: auth_headers(user_record).merge('Idempotency-Key' => key), as: :json
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body).dig('error', 'code')).to eq('IDEMPOTENCY_CONFLICT')
    end

    it 'rejects an empty cart and rolls back all reservations when one item fails' do
      user_record = user
      address = address_for(user_record)
      method = shipping_method
      post '/checkout', params: { address_id: address.id, shipping_method_id: method.id }, headers: auth_headers(user_record).merge('Idempotency-Key' => SecureRandom.uuid), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig('error', 'code')).to eq('CART_EMPTY')

      category = category_record
      available = product_record(category, stock_on_hand: 5)
      unavailable = product_record(category, stock_on_hand: 1)
      add_to_cart(user_record, available, 2)
      CartItem.create!(cart: user_record.carts.first, product: unavailable, quantity: 2)
      post '/checkout', params: { address_id: address.id, shipping_method_id: method.id }, headers: auth_headers(user_record).merge('Idempotency-Key' => SecureRandom.uuid), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(available.reload.reserved_stock).to eq(0)
      expect(unavailable.reload.reserved_stock).to eq(0)
      expect(InventoryReservation.where(order_id: Order.where(user: user_record).select(:id))).to be_empty
    end

    it 'does not expose another user order' do
      owner = user
      other = user
      product = product_record(category_record)
      address = address_for(owner)
      add_to_cart(owner, product, 1)
      post '/checkout', params: { address_id: address.id, shipping_method_id: shipping_method.id }, headers: auth_headers(owner).merge('Idempotency-Key' => SecureRandom.uuid), as: :json
      order_id = JSON.parse(response.body).dig('data', 'order', 'id')

      get "/customer/orders/#{order_id}", headers: auth_headers(other)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'reservation expiry' do
    it 'releases expired reservations and keeps reservations with uploaded proof' do
      owner = user
      product = product_record(category_record, stock_on_hand: 3)
      address = address_for(owner)
      add_to_cart(owner, product, 2)
      post '/checkout', params: { address_id: address.id, shipping_method_id: shipping_method.id }, headers: auth_headers(owner).merge('Idempotency-Key' => SecureRandom.uuid), as: :json
      reservation = Order.last.inventory_reservations.first
      reservation.update!(expires_at: 1.minute.ago)

      InventoryReservationExpiryService.call
      expect(reservation.reload.status).to eq('released')
      expect(product.reload.reserved_stock).to eq(0)
      expect(reservation.order.reload.status).to eq('cancelled')
      expect(reservation.order.payment.status).to eq('expired')

      second_product = product_record(category_record, stock_on_hand: 3)
      add_to_cart(owner, second_product, 1)
      post '/checkout', params: { address_id: address.id, shipping_method_id: shipping_method.id }, headers: auth_headers(owner).merge('Idempotency-Key' => SecureRandom.uuid), as: :json
      second_reservation = Order.last.inventory_reservations.first
      second_reservation.update!(expires_at: 1.minute.ago)
      PaymentProof.create!(payment: second_reservation.order.payment, storage_key: 'private/proof', original_filename: 'proof.png', file_size: 10, uploaded_at: second_reservation.expires_at - 1.minute, status: 'submitted')
      InventoryReservationExpiryService.call
      expect(second_reservation.reload.status).to eq('reserved')
      expect(second_product.reload.reserved_stock).to eq(1)
    end

    it 'does not release more reserved stock than the product has' do
      owner = user
      product = product_record(category_record, stock_on_hand: 3)
      address = address_for(owner)
      add_to_cart(owner, product, 1)
      post '/checkout', params: { address_id: address.id, shipping_method_id: shipping_method.id }, headers: auth_headers(owner).merge('Idempotency-Key' => SecureRandom.uuid), as: :json
      reservation = Order.last.inventory_reservations.first
      reservation.update!(expires_at: 1.minute.ago)
      product.update_columns(reserved_stock: 0)

      InventoryReservationExpiryService.call

      expect(reservation.reload.status).to eq('reserved')
      expect(product.reload.reserved_stock).to eq(0)
      expect(reservation.order.reload.status).to eq('awaiting_payment')
    end
  end
end
