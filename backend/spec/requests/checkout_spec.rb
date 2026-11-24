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

  def checkout_setup
    customer = user
    product = product_record(category_record)
    address = address_for(customer)
    method = shipping_method
    add_to_cart(customer, product, 1)
    [ customer, product, address, method, customer.carts.find_by!(user: customer) ]
  end

  def post_checkout(customer, address, method, key)
    post '/checkout',
      params: { address_id: address.id, shipping_method_id: method.id },
      headers: auth_headers(customer).merge('Idempotency-Key' => key),
      as: :json
  end

  def expect_checkout_rolled_back(customer:, product:, cart:, key:)
    expect(Order.where(user: customer)).to be_empty
    expect(OrderItem.joins(:order).where(orders: { user_id: customer.id })).to be_empty
    expect(Payment.joins(:order).where(orders: { user_id: customer.id })).to be_empty
    expect(InventoryReservation.joins(:order).where(orders: { user_id: customer.id })).to be_empty
    expect(InventoryMovement.where(product: product)).to be_empty
    expect(product.reload.reserved_stock).to eq(0)
    expect(cart.cart_items.count).to eq(1)
    expect(IdempotencyKey.where(user: customer, key: key)).to be_empty
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
      expect(InventoryMovement.where(order: order, movement_type: 'reservation').first).to have_attributes(product_id: product.id, quantity: 2, stock_before: 5, stock_after: 3, created_by: user_record)
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
      original_body = JSON.parse(response.body)
      post '/checkout', params: payload, headers: auth_headers(user_record).merge('Idempotency-Key' => key), as: :json
      expect(response).to have_http_status(:created)
      expect(Order.where(user: user_record).count).to eq(order_count)
      expect(JSON.parse(response.body)).to eq(original_body)
      idempotency = IdempotencyKey.find_by!(user: user_record, key: key)
      expect(idempotency.response_status).to eq(201)
      expect(JSON.parse(idempotency.response_body)).to eq(original_body)
      expect(idempotency.resource_id).to eq(original_body.dig('data', 'order', 'id').to_s)

      post '/checkout', params: payload.merge(customer_notes: 'changed'), headers: auth_headers(user_record).merge('Idempotency-Key' => key), as: :json
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body).dig('error', 'code')).to eq('IDEMPOTENCY_CONFLICT')
    end

    it 'returns CHECKOUT_BUSY when the idempotency lookup hits a SQLite busy timeout' do
      customer, _product, address, method, = checkout_setup
      key = SecureRandom.uuid
      busy_exception = SQLite3::BusyException.new('database is locked')
      timeout_error = ActiveRecord::StatementTimeout.new('database is locked')
      allow(timeout_error).to receive(:cause).and_return(busy_exception)
      lookup_count = 0

      allow(CheckoutService).to receive(:call) do
        raise ActiveRecord::StatementInvalid.new('database is locked'), cause: busy_exception
      end
      allow(IdempotencyKey).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
        lookup_count += 1
        if lookup_count == 2
          raise timeout_error
        end

        original.call(*args, **kwargs)
      end

      post_checkout(customer, address, method, key)

      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body).dig('error', 'code')).to eq('CHECKOUT_BUSY')
    end

    it 'propagates non-busy database errors from the idempotency lookup' do
      customer, _product, address, method, = checkout_setup
      key = SecureRandom.uuid
      busy_exception = SQLite3::BusyException.new('database is locked')
      database_error = ActiveRecord::StatementInvalid.new('database query failed')
      lookup_count = 0

      allow(CheckoutService).to receive(:call) do
        raise ActiveRecord::StatementInvalid.new('database is locked'), cause: busy_exception
      end
      allow(IdempotencyKey).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
        lookup_count += 1
        if lookup_count == 2
          raise database_error
        end

        original.call(*args, **kwargs)
      end

      expect { post_checkout(customer, address, method, key) }
        .to raise_error(ActiveRecord::StatementInvalid, 'database query failed')
    end

    it 'isolates the same idempotency key for different users' do
      first_user, first_product, first_address, method, = checkout_setup
      second_user = user
      second_address = address_for(second_user)
      second_product = product_record(category_record)
      add_to_cart(second_user, second_product, 1)
      key = SecureRandom.uuid

      post_checkout(first_user, first_address, method, key)
      first_order_id = JSON.parse(response.body).dig('data', 'order', 'id')
      post_checkout(second_user, second_address, method, key)
      second_order_id = JSON.parse(response.body).dig('data', 'order', 'id')

      expect(response).to have_http_status(:created)
      expect(first_order_id).not_to eq(second_order_id)
      expect(IdempotencyKey.where(key: key).pluck(:user_id)).to contain_exactly(first_user.id, second_user.id)
      expect(first_product.reload.reserved_stock).to eq(1)
      expect(second_product.reload.reserved_stock).to eq(1)
    end

    it 'rolls back the idempotency row and all checkout writes when order creation fails' do
      customer, product, address, method, cart = checkout_setup
      key = SecureRandom.uuid
      allow(Order).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'injected order failure')

      expect { post_checkout(customer, address, method, key) }.to raise_error(ActiveRecord::StatementInvalid, 'injected order failure')

      expect_checkout_rolled_back(customer:, product:, cart:, key:)
    end

    it 'rolls back prior reservations when reservation creation fails' do
      customer, product, address, method, cart = checkout_setup
      key = SecureRandom.uuid
      allow(InventoryReservation).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'injected reservation failure')

      expect { post_checkout(customer, address, method, key) }.to raise_error(ActiveRecord::StatementInvalid, 'injected reservation failure')

      expect_checkout_rolled_back(customer:, product:, cart:, key:)
    end

    it 'rolls back order and reservation writes when payment creation fails' do
      customer, product, address, method, cart = checkout_setup
      key = SecureRandom.uuid
      allow(Payment).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'injected payment failure')

      expect { post_checkout(customer, address, method, key) }.to raise_error(ActiveRecord::StatementInvalid, 'injected payment failure')

      expect_checkout_rolled_back(customer:, product:, cart:, key:)
    end

    it 'rolls back checkout writes when cart clearing fails' do
      customer, product, address, method, cart = checkout_setup
      key = SecureRandom.uuid
      item_scope = CartItem.where(cart_id: cart.id)
      allow(CartItem).to receive(:where).with(cart_id: cart.id).and_return(item_scope)
      allow(item_scope).to receive(:delete_all).and_raise(ActiveRecord::StatementInvalid, 'injected cart clear failure')

      expect { post_checkout(customer, address, method, key) }.to raise_error(ActiveRecord::StatementInvalid, 'injected cart clear failure')

      expect_checkout_rolled_back(customer:, product:, cart:, key:)
    end

    it 'rolls back checkout writes when response replay persistence fails' do
      customer, product, address, method, cart = checkout_setup
      key = SecureRandom.uuid
      allow_any_instance_of(IdempotencyKey).to receive(:update!).and_wrap_original do |original, *args, **attributes|
        raise ActiveRecord::StatementInvalid, 'injected response persistence failure' if attributes.key?(:response_body)

        original.call(*args, **attributes)
      end

      expect { post_checkout(customer, address, method, key) }.to raise_error(ActiveRecord::StatementInvalid, 'injected response persistence failure')

      expect_checkout_rolled_back(customer:, product:, cart:, key:)
    end

    it 'serializes simultaneous requests with the same key and replays one committed result' do
      customer, product, address, method, cart = checkout_setup
      key = SecureRandom.uuid
      headers = auth_headers(customer).merge('Idempotency-Key' => key)
      payload = { address_id: address.id, shipping_method_id: method.id }
      ready = Queue.new
      start = Queue.new
      results = Queue.new
      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            session = ActionDispatch::Integration::Session.new(Rails.application)
            ready << true
            start.pop
            session.post('/checkout', params: payload, headers: headers, as: :json)
            results << [ session.response.status, JSON.parse(session.response.body) ]
          end
        rescue StandardError => error
          results << error
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:join)
      outcomes = 2.times.map { results.pop }

      expect(outcomes).to all(be_a(Array))
      expect(outcomes.map(&:first)).to eq([ 201, 201 ])
      order_ids = outcomes.map { |outcome| outcome.last.dig('data', 'order', 'id') }
      expect(order_ids.uniq.length).to eq(1)
      expect(Order.where(user: customer).count).to eq(1)
      expect(Payment.joins(:order).where(orders: { user_id: customer.id }).count).to eq(1)
      expect(InventoryReservation.joins(:order).where(orders: { user_id: customer.id }).count).to eq(1)
      expect(InventoryMovement.where(product: product, movement_type: 'reservation').count).to eq(1)
      expect(IdempotencyKey.where(user: customer, key: key).count).to eq(1)
      expect(JSON.parse(IdempotencyKey.find_by!(user: customer, key: key).response_body)).to eq(outcomes.first.last)
      expect(product.reload.reserved_stock).to eq(1)
      expect(cart.cart_items).to be_empty
    ensure
      threads&.each(&:join)
    end

    it 'rejects an empty cart and rolls back all reservations when one item fails' do
      user_record = user
      address = address_for(user_record)
      method = shipping_method
      empty_cart_key = SecureRandom.uuid
      post '/checkout', params: { address_id: address.id, shipping_method_id: method.id }, headers: auth_headers(user_record).merge('Idempotency-Key' => empty_cart_key), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig('error', 'code')).to eq('CART_EMPTY')
      expect(IdempotencyKey.where(user: user_record, key: empty_cart_key)).to be_empty

      category = category_record
      available = product_record(category, stock_on_hand: 5)
      unavailable = product_record(category, stock_on_hand: 1)
      add_to_cart(user_record, available, 2)
      CartItem.create!(cart: user_record.carts.first, product: unavailable, quantity: 2)
      partial_checkout_key = SecureRandom.uuid
      post '/checkout', params: { address_id: address.id, shipping_method_id: method.id }, headers: auth_headers(user_record).merge('Idempotency-Key' => partial_checkout_key), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(available.reload.reserved_stock).to eq(0)
      expect(unavailable.reload.reserved_stock).to eq(0)
      expect(InventoryReservation.where(order_id: Order.where(user: user_record).select(:id))).to be_empty
      expect(InventoryMovement.where(product: [ available, unavailable ])).to be_empty
      expect(IdempotencyKey.where(user: user_record, key: partial_checkout_key)).to be_empty
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
