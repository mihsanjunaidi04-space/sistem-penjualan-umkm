require 'rails_helper'

RSpec.describe 'Admin manual refunds API', type: :request do
  def user(role: 'customer', suffix: SecureRandom.hex(4))
    User.create!(name: "Refund User #{suffix}", email: "refund-#{suffix}@example.com", password: 'password123', role: role)
  end

  def headers(record)
    { 'Authorization' => "Bearer #{JwtService.encode({ user_id: record.id, role: record.role })}" }
  end

  def paid_payment(amount: 100_000)
    customer = user
    category = Category.create!(name: "Refund Cat #{SecureRandom.hex(3)}", slug: "refund-cat-#{SecureRandom.hex(3)}")
    product = Product.create!(category: category, name: 'Refund product', slug: "refund-product-#{SecureRandom.hex(3)}", sku: "REF-#{SecureRandom.hex(3)}", price: amount, stock_on_hand: 5, reserved_stock: 0, is_active: true)
    method = ShippingMethod.create!(name: "Refund ship #{SecureRandom.hex(3)}", estimated_days: 2, cost: 0, is_active: true)
    order = Order.create!(order_number: "REF-#{SecureRandom.hex(5)}", user: customer, shipping_method: method, status: 'processing', subtotal: amount, shipping_cost: 0, total_amount: amount, payment_deadline_at: 12.hours.from_now)
    payment = Payment.create!(order: order, payment_method: 'manual_transfer', amount: amount, status: 'paid')
    [ order, product, payment ]
  end

  def create_refund(payment, admin, amount:, reason: 'Pembatalan pesanan', key: SecureRandom.uuid)
    post "/admin/payments/#{payment.id}/refunds", params: { refund: { amount: amount, reason: reason } }, headers: headers(admin).merge('Idempotency-Key' => key), as: :json
  end

  def parallel_refund_requests(payment, admin, key:, amounts: [ 10_000, 10_000 ], reason: 'Refund concurrent')
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = amounts.map do |amount|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          session = ActionDispatch::Integration::Session.new(Rails.application)
          ready << true
          start.pop
          session.post("/admin/payments/#{payment.id}/refunds", params: { refund: { amount:, reason: } }, headers: headers(admin).merge('Idempotency-Key' => key), as: :json)
          results << [ session.response.status, session.response.body ]
        end
      rescue StandardError => error
        results << error
      end
    end
    amounts.length.times { ready.pop }
    amounts.length.times { start << true }
    threads.each(&:join)
    amounts.length.times.map { results.pop }
  ensure
    threads&.each(&:join)
  end

  it 'requires a nonblank Idempotency-Key no longer than 180 characters' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')

    post "/admin/payments/#{payment.id}/refunds", params: { refund: { amount: 1_000, reason: 'Valid reason' } }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body).dig('error', 'code')).to eq('IDEMPOTENCY_KEY_REQUIRED')

    post "/admin/payments/#{payment.id}/refunds", params: { refund: { amount: 1_000, reason: 'Valid reason' } }, headers: headers(admin).merge('Idempotency-Key' => 'k' * 181), as: :json
    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body).dig('error', 'code')).to eq('IDEMPOTENCY_KEY_INVALID')
    expect(Refund.where(payment: payment)).to be_empty
  end

  it 'replays the same refund without creating another refund or audit log' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')
    key = SecureRandom.uuid
    create_refund(payment, admin, amount: 20_000, reason: 'same payload', key:)
    expect(response).to have_http_status(:created)
    refund_id = JSON.parse(response.body).dig('data', 'refund', 'id')
    audit_count = AuditLog.where(user: admin, action: 'refund_created').count

    create_refund(payment, admin, amount: 20_000, reason: 'same payload', key:)

    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body).dig('data', 'refund', 'id')).to eq(refund_id)
    expect(Refund.where(payment: payment).count).to eq(1)
    expect(RefundIdempotencyKey.where(admin:, payment:, key:).count).to eq(1)
    expect(AuditLog.where(user: admin, action: 'refund_created').count).to eq(audit_count)
  end

  it 'returns conflict for a reused key with a different business payload' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')
    key = SecureRandom.uuid
    create_refund(payment, admin, amount: 20_000, reason: 'reason one', key:)
    audit_count = AuditLog.where(user: admin, action: 'refund_created').count

    create_refund(payment, admin, amount: 21_000, reason: 'reason one', key:)

    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body).dig('error', 'code')).to eq('REFUND_IDEMPOTENCY_CONFLICT')

    create_refund(payment, admin, amount: 20_000, reason: 'reason two', key:)

    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body).dig('error', 'code')).to eq('REFUND_IDEMPOTENCY_CONFLICT')
    expect(Refund.where(payment: payment).count).to eq(1)
    expect(AuditLog.where(user: admin, action: 'refund_created').count).to eq(audit_count)
  end

  it 'treats a different key as a new refund subject to the aggregate cap' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')

    create_refund(payment, admin, amount: 20_000, key: 'refund-key-one')
    create_refund(payment, admin, amount: 30_000, key: 'refund-key-two')

    expect(response).to have_http_status(:created)
    expect(Refund.where(payment: payment, status: 'pending').sum(:amount)).to eq(50_000)
    expect(RefundIdempotencyKey.where(admin:, payment:).count).to eq(2)
  end

  it 'isolates an identical key across payments and admins' do
    _order_a, _product_a, payment_a = paid_payment
    _order_b, _product_b, payment_b = paid_payment
    admin_a = user(role: 'admin')
    admin_b = user(role: 'admin')

    create_refund(payment_a, admin_a, amount: 10_000, reason: 'same', key: 'shared-key')
    first_refund_id = JSON.parse(response.body).dig('data', 'refund', 'id')
    create_refund(payment_b, admin_a, amount: 10_000, reason: 'same', key: 'shared-key')
    second_refund_id = JSON.parse(response.body).dig('data', 'refund', 'id')
    create_refund(payment_a, admin_b, amount: 10_000, reason: 'same', key: 'shared-key')
    third_refund_id = JSON.parse(response.body).dig('data', 'refund', 'id')

    expect([ first_refund_id, second_refund_id, third_refund_id ].uniq.length).to eq(3)
    expect(RefundIdempotencyKey.where(key: 'shared-key').count).to eq(3)
  end

  it 'creates only one refund and audit entry for concurrent identical requests' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')
    outcomes = parallel_refund_requests(payment, admin, key: 'concurrent-same-key')

    expect(outcomes).to all(be_a(Array))
    expect(outcomes.map(&:first)).to eq([ 201, 201 ])
    refund_ids = outcomes.map { |status, body| JSON.parse(body).dig('data', 'refund', 'id') }
    expect(refund_ids.uniq.length).to eq(1)
    expect(Refund.where(payment: payment).count).to eq(1)
    expect(RefundIdempotencyKey.where(admin:, payment:, key: 'concurrent-same-key').count).to eq(1)
    expect(AuditLog.where(user: admin, action: 'refund_created').count).to eq(1)
  end

  it 'does not create two refunds for concurrent requests using one key with different payloads' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')
    outcomes = parallel_refund_requests(payment, admin, key: 'concurrent-conflict-key', amounts: [ 10_000, 20_000 ])

    expect(outcomes).to all(be_a(Array))
    expect(outcomes.map(&:first).sort).to eq([ 201, 409 ])
    expect(Refund.where(payment: payment).count).to eq(1)
    expect(RefundIdempotencyKey.where(admin:, payment:, key: 'concurrent-conflict-key').count).to eq(1)
    expect(AuditLog.where(user: admin, action: 'refund_created').count).to eq(1)
  end

  it 'rolls back refund and idempotency record if audit logging fails' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')
    allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'audit write failed')

    expect {
      create_refund(payment, admin, amount: 10_000, key: 'audit-failure-key')
    }.to raise_error(ActiveRecord::StatementInvalid, 'audit write failed')

    expect(Refund.where(payment: payment)).to be_empty
    expect(RefundIdempotencyKey.where(admin:, payment:, key: 'audit-failure-key')).to be_empty
  end

  it 'rolls back refund and idempotency record if idempotency storage fails' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')
    allow(RefundIdempotencyKey).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'idempotency write failed')

    expect {
      create_refund(payment, admin, amount: 10_000, key: 'idempotency-failure-key')
    }.to raise_error(ActiveRecord::StatementInvalid, 'idempotency write failed')

    expect(Refund.where(payment: payment)).to be_empty
    expect(RefundIdempotencyKey.where(admin:, payment:, key: 'idempotency-failure-key')).to be_empty
    expect(AuditLog.where(user: admin, action: 'refund_created')).to be_empty
  end

  it 'does not persist an idempotency record if refund creation fails' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')
    allow(Refund).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'refund write failed')

    expect {
      create_refund(payment, admin, amount: 10_000, key: 'refund-failure-key')
    }.to raise_error(ActiveRecord::StatementInvalid, 'refund write failed')

    expect(RefundIdempotencyKey.where(admin:, payment:, key: 'refund-failure-key')).to be_empty
    expect(AuditLog.where(user: admin, action: 'refund_created')).to be_empty
  end

  it 'allows admin to create a pending refund and ignores client status and linkage fields' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')

    post "/admin/payments/#{payment.id}/refunds", params: { refund: { amount: 25_000, reason: 'Pengembalian sebagian', status: 'processed', order_id: 999, payment_id: 999, processed_by: admin.id, reference_number: 'FORGED' } }, headers: headers(admin).merge('Idempotency-Key' => SecureRandom.uuid), as: :json

    expect(response).to have_http_status(:created)
    refund = Refund.find(JSON.parse(response.body).dig('data', 'refund', 'id'))
    expect(refund).to have_attributes(payment_id: payment.id, order_id: payment.order_id, amount: 25_000, status: 'pending', processed_by: nil, reference_number: nil)
    expect(AuditLog.where(user: admin, action: 'refund_created', resource_id: refund.id.to_s)).to exist
  end

  it 'rejects unauthenticated and non-admin access and exposes no customer refund route' do
    _order, _product, payment = paid_payment
    customer = user

    post "/admin/payments/#{payment.id}/refunds", params: { refund: { amount: 1, reason: 'test' } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "/admin/payments/#{payment.id}/refunds", params: { refund: { amount: 1, reason: 'test' } }, headers: headers(customer).merge('Idempotency-Key' => SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:forbidden)
    get '/admin/refunds', headers: headers(customer)
    expect(response).to have_http_status(:forbidden)
  end

  it 'requires a paid payment and validates the amount and reason' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')
    payment.update!(status: 'waiting_verification')

    create_refund(payment, admin, amount: 1)
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).dig('error', 'code')).to eq('REFUND_PAYMENT_NOT_PAID')

    payment.update!(status: 'paid')
    create_refund(payment, admin, amount: '1.5')
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).dig('error', 'code')).to eq('REFUND_AMOUNT_INVALID')
    expect(Refund.where(payment: payment)).to be_empty
  end

  it 'allows partial and full refunds and changes payment state only when processed total is full' do
    order, product, payment = paid_payment
    admin = user(role: 'admin')
    create_refund(payment, admin, amount: 40_000)
    partial = Refund.find(JSON.parse(response.body).dig('data', 'refund', 'id'))
    expect(partial.status).to eq('pending')

    post "/admin/refunds/#{partial.id}/process", params: { refund: { reference_number: 'BANK-REF-1' } }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(partial.reload.status).to eq('processed')
    expect(payment.reload.status).to eq('paid')

    create_refund(payment, admin, amount: 60_000)
    full = Refund.find(JSON.parse(response.body).dig('data', 'refund', 'id'))
    post "/admin/refunds/#{full.id}/process", params: { refund: { reference_number: 'BANK-REF-2' } }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(payment.reload.status).to eq('refunded')
    expect(order.reload.status).to eq('processing')
    expect(product.reload).to have_attributes(stock_on_hand: 5, reserved_stock: 0)
    expect(AuditLog.where(user: admin, action: 'refund_processed').count).to eq(2)
  end

  it 'counts pending refunds against the cap but excludes rejected refunds' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')
    create_refund(payment, admin, amount: 60_000)
    pending = Refund.find(JSON.parse(response.body).dig('data', 'refund', 'id'))
    create_refund(payment, admin, amount: 41_000)
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).dig('error', 'code')).to eq('REFUND_LIMIT_EXCEEDED')

    post "/admin/refunds/#{pending.id}/reject", params: { refund: { notes: 'Tidak memenuhi kebijakan.' } }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(pending.reload.status).to eq('rejected')

    create_refund(payment, admin, amount: 100_000)
    expect(response).to have_http_status(:created)
    expect(Refund.where(payment: payment, status: 'pending').sum(:amount)).to eq(100_000)
    expect(AuditLog.where(user: admin, action: 'refund_rejected', resource_id: pending.id.to_s)).to exist
  end

  it 'requires a transfer reference and rejects repeat processing or rejection' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')
    create_refund(payment, admin, amount: 10_000)
    refund = Refund.find(JSON.parse(response.body).dig('data', 'refund', 'id'))

    post "/admin/refunds/#{refund.id}/process", params: { refund: { reference_number: ' ' } }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(refund.reload.status).to eq('pending')

    post "/admin/refunds/#{refund.id}/process", params: { refund: { reference_number: 'BANK-REF-3' } }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    post "/admin/refunds/#{refund.id}/process", params: { refund: { reference_number: 'BANK-REF-4' } }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    post "/admin/refunds/#{refund.id}/reject", params: { refund: { notes: 'late rejection' } }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(refund.reload.reference_number).to eq('BANK-REF-3')
  end

  it 'requires a rejection note and lists refunds only to admins' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')
    create_refund(payment, admin, amount: 10_000)
    refund = Refund.find(JSON.parse(response.body).dig('data', 'refund', 'id'))

    post "/admin/refunds/#{refund.id}/reject", params: { refund: { notes: ' ' } }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    post "/admin/refunds/#{refund.id}/reject", params: { refund: { notes: 'Transfer tidak dapat diverifikasi.' } }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    get '/admin/refunds?status=rejected', headers: headers(admin)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig('data', 'refunds').pluck('id')).to include(refund.id)
    get "/admin/refunds/#{refund.id}", headers: headers(admin)
    expect(response).to have_http_status(:ok)
  end

  it 'rolls back refund and payment changes if audit logging fails' do
    order, _product, payment = paid_payment
    admin = user(role: 'admin')
    create_refund(payment, admin, amount: 100_000)
    refund = Refund.find(JSON.parse(response.body).dig('data', 'refund', 'id'))
    failure = ActiveRecord::StatementInvalid.new('audit write failed')
    allow(AuditLog).to receive(:create!).and_raise(failure)

    expect {
      post "/admin/refunds/#{refund.id}/process", params: { refund: { reference_number: 'BANK-REF-5' } }, headers: headers(admin), as: :json
    }.to raise_error(ActiveRecord::StatementInvalid, 'audit write failed')

    expect(refund.reload.status).to eq('pending')
    expect(payment.reload.status).to eq('paid')
    expect(order.reload.status).to eq('processing')
  end

  it 'does not allow simultaneous requests to exceed the payment refund cap' do
    _order, _product, payment = paid_payment
    admin = user(role: 'admin')
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          session = ActionDispatch::Integration::Session.new(Rails.application)
          ready << true
          start.pop
          session.post("/admin/payments/#{payment.id}/refunds", params: { refund: { amount: 60_000, reason: 'Refund concurrent' } }, headers: headers(admin).merge('Idempotency-Key' => SecureRandom.uuid), as: :json)
          results << session.response.status
        end
      rescue StandardError => error
        results << error
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop }

    expect(outcomes).to all(be_a(Integer))
    expect(outcomes.sort).to eq([ 201, 422 ])
    expect(payment.refunds.where(status: %w[pending processed]).sum(:amount)).to eq(60_000)
    expect(payment.reload.status).to eq('paid')
  ensure
    threads&.each(&:join)
  end

  it 'allows only one of two admins to process the same refund concurrently' do
    _order, _product, payment = paid_payment
    creator = user(role: 'admin')
    first_admin = user(role: 'admin')
    second_admin = user(role: 'admin')
    create_refund(payment, creator, amount: 100_000)
    refund = Refund.find(JSON.parse(response.body).dig('data', 'refund', 'id'))
    admins = [ first_admin, second_admin ]
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = admins.map do |admin|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          session = ActionDispatch::Integration::Session.new(Rails.application)
          ready << true
          start.pop
          session.post("/admin/refunds/#{refund.id}/process", params: { refund: { reference_number: "BANK-#{admin.id}" } }, headers: headers(admin), as: :json)
          results << session.response.status
        end
      rescue StandardError => error
        results << error
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop }

    expect(outcomes).to all(be_a(Integer))
    expect(outcomes.sort).to eq([ 200, 422 ])
    expect(refund.reload.status).to eq('processed')
    expect(admins).to include(refund.processed_by)
    expect(AuditLog.where(action: 'refund_processed', resource_id: refund.id.to_s).count).to eq(1)
    expect(payment.reload.status).to eq('refunded')
  ensure
    threads&.each(&:join)
  end
end
