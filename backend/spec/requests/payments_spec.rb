require 'rails_helper'
require 'tmpdir'
require 'pathname'

RSpec.describe 'Manual transfer payment API', type: :request do
  around do |example|
    Dir.mktmpdir('payment-proof-upload-') do |dir|
      @tmp_root = Pathname.new(dir)
      original_env = ENV['PAYMENT_PROOF_TEST_ROOT']
      ENV['PAYMENT_PROOF_TEST_ROOT'] = @tmp_root.to_s
      example.run
    ensure
      ENV['PAYMENT_PROOF_TEST_ROOT'] = original_env
    end
  end

  let(:root) { @tmp_root }

  def user(role: 'customer', suffix: SecureRandom.hex(4))
    User.create!(name: "Payment User #{suffix}", email: "payment-#{suffix}@example.com", password: 'password123', role: role)
  end

  def headers(record)
    { 'Authorization' => "Bearer #{JwtService.encode({ user_id: record.id, role: record.role })}" }
  end

  def order_for(customer)
    category = Category.create!(name: "Payment Cat #{SecureRandom.hex(3)}", slug: "payment-cat-#{SecureRandom.hex(3)}")
    product = Product.create!(category: category, name: 'Payment product', slug: "payment-product-#{SecureRandom.hex(3)}", sku: "PAY-#{SecureRandom.hex(3)}", price: 50_000, stock_on_hand: 3, reserved_stock: 1, is_active: true)
    method = ShippingMethod.create!(name: "Payment ship #{SecureRandom.hex(3)}", estimated_days: 2, cost: 0, is_active: true)
    order = Order.create!(order_number: "PAY-#{SecureRandom.hex(5)}", user: customer, shipping_method: method, status: 'awaiting_payment', subtotal: 50_000, shipping_cost: 0, total_amount: 50_000, payment_deadline_at: 12.hours.from_now)
    OrderItem.create!(order: order, product: product, product_name_snapshot: product.name, sku_snapshot: product.sku, unit_price: 50_000, quantity: 1, subtotal: 50_000)
    InventoryReservation.create!(order: order, product: product, quantity: 1, status: 'reserved', expires_at: order.payment_deadline_at)
    payment = Payment.create!(order: order, payment_method: 'manual_transfer', amount: 50_000, status: 'pending')
    [ order, product, payment ]
  end

  def png_upload(name = 'proof.png')
    fixture = Rails.root.join('tmp', "#{SecureRandom.hex}.png")
    File.binwrite(fixture, "\x89PNG\r\n\x1a\n".b + ('0' * 100))
    Rack::Test::UploadedFile.new(fixture, 'image/png', original_filename: name)
  end

  it 'validates upload, preserves ownership, and exposes no public proof URL' do
    customer = user
    owner, = order_for(customer)
    other = user
    post "/customer/orders/#{owner.id}/payment-proof", params: { proof: png_upload }, headers: headers(other)
    expect(response).to have_http_status(:not_found)
    post "/customer/orders/#{owner.id}/payment-proof", params: { proof: png_upload('proof.txt') }, headers: headers(customer)
    expect(response).to have_http_status(:unprocessable_content)
    post "/customer/orders/#{owner.id}/payment-proof", params: { proof: png_upload }, headers: headers(customer)
    expect(response).to have_http_status(:created)
    expect(owner.payment.reload.status).to eq('waiting_verification')
    expect(JSON.parse(response.body).dig('data', 'payment', 'proofs', 0, 'url')).to be_nil
    file = PrivatePaymentProofStorage.open(owner.payment.payment_proofs.first.storage_key, root: root)
    expect(File.dirname(file.path.to_s)).to eq(root.to_s)
    file.close
  end

  it 'ignores client-controlled root parameter and stores at test root' do
    customer = user
    owner, = order_for(customer)
    foreign_root = Dir.mktmpdir('foreign-root-')
    begin
      post "/customer/orders/#{owner.id}/payment-proof",
        params: { proof: png_upload, root: foreign_root },
        headers: headers(customer)
      expect(response).to have_http_status(:created)
      proof = owner.payment.payment_proofs.first
      expect(File.exist?(File.join(foreign_root, proof.storage_key))).to be false
      expect(File.exist?(File.join(root.to_s, proof.storage_key))).to be true
    ensure
      FileUtils.remove_entry(foreign_root) if foreign_root && Dir.exist?(foreign_root)
    end
  end

  it 'allows admin approval once and converts reservations atomically' do
    customer = user
    admin = user(role: 'admin')
    order, product, payment = order_for(customer)
    post "/customer/orders/#{order.id}/payment-proof", params: { proof: png_upload }, headers: headers(customer)
    expect(response).to have_http_status(:created)
    post "/admin/payments/#{payment.id}/approve", headers: headers(admin)
    expect(response).to have_http_status(:ok)
    expect(payment.reload.status).to eq('paid')
    expect(order.reload.status).to eq('processing')
    expect(product.reload).to have_attributes(stock_on_hand: 2, reserved_stock: 0)
    expect(order.inventory_reservations.first.reload.status).to eq('converted')
    expect(InventoryMovement.where(order: order, movement_type: 'stock_out').count).to eq(1)
    expect(AuditLog.where(action: 'payment_approved', resource_id: payment.id.to_s).count).to eq(1)
    post "/admin/payments/#{payment.id}/approve", headers: headers(admin)
    expect(response).to have_http_status(:unprocessable_content)
    expect(product.reload.stock_on_hand).to eq(2)
  end

  it 'rejects with reason and permits resubmission before deadline' do
    customer = user
    admin = user(role: 'admin')
    order, = order_for(customer)
    post "/customer/orders/#{order.id}/payment-proof", params: { proof: png_upload }, headers: headers(customer)
    post "/admin/payments/#{order.payment.id}/reject", params: { reason: 'Nominal tidak terbaca' }, headers: headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(order.payment.reload.status).to eq('rejected')
    expect(order.reload.status).to eq('awaiting_payment')
    post "/customer/orders/#{order.id}/payment-proof", params: { proof: png_upload('retry.png') }, headers: headers(customer)
    expect(response).to have_http_status(:created)
    expect(order.payment.reload.status).to eq('waiting_verification')
    expect(order.payment.verification_events.count).to eq(1)
  end

  it 'does not permit customer verification or access to another proof' do
    customer = user
    other = user
    order, = order_for(customer)
    post "/customer/orders/#{order.id}/payment-proof", params: { proof: png_upload }, headers: headers(customer)
    expect(order.payment.reload.status).to eq('waiting_verification')
    post "/admin/payments/#{order.payment.id}/approve", headers: headers(customer)
    expect(response).to have_http_status(:forbidden)
    proof_id = order.payment.payment_proofs.first.id
    get "/customer/orders/#{order.id}/payment-proofs/#{proof_id}", headers: headers(other)
    expect(response).to have_http_status(:not_found)
  end

  it 'serves a proof only to its owner or an authorized admin' do
    customer = user
    admin = user(role: 'admin')
    other = user
    order, = order_for(customer)
    post "/customer/orders/#{order.id}/payment-proof", params: { proof: png_upload }, headers: headers(customer)
    proof = order.payment.payment_proofs.first
    proof_id = proof.id

    get "/customer/orders/#{order.id}/payment-proofs/#{proof_id}", headers: headers(customer)
    expect(response).to have_http_status(:ok)

    get "/customer/orders/#{order.id}/payment-proofs/#{proof_id}", headers: headers(other)
    expect(response).to have_http_status(:not_found)

    get "/admin/payments/#{order.payment.id}/proofs/#{proof_id}", headers: headers(other)
    expect(response).to have_http_status(:forbidden)

    get "/admin/payments/#{order.payment.id}/proofs/#{proof_id}", headers: headers(admin)
    expect(response).to have_http_status(:ok)
  end

  it 'rolls back approval when inventory becomes inconsistent' do
    customer = user
    admin = user(role: 'admin')
    order, product, payment = order_for(customer)
    post "/customer/orders/#{order.id}/payment-proof", params: { proof: png_upload }, headers: headers(customer)
    product.update!(reserved_stock: 0)
    post "/admin/payments/#{payment.id}/approve", headers: headers(admin)
    expect(response).to have_http_status(:unprocessable_content)
    expect(payment.reload.status).to eq('waiting_verification')
    expect(order.reload.status).to eq('awaiting_payment')
    expect(order.inventory_reservations.first.reload.status).to eq('reserved')
    expect(InventoryMovement.where(order: order, movement_type: 'stock_out')).to be_empty
  end

  it 'rolls back payment approval when the audit log cannot be created' do
    customer = user
    admin = user(role: 'admin')
    order, product, payment = order_for(customer)
    post "/customer/orders/#{order.id}/payment-proof", params: { proof: png_upload }, headers: headers(customer)
    proof = payment.payment_proofs.first
    failure = ActiveRecord::StatementInvalid.new('audit log write failed')

    allow(AuditLog).to receive(:create!).and_raise(failure)

    expect {
      PaymentApprovalService.approve!(
        payment_id: payment.id,
        admin: admin,
        request: instance_double(ActionDispatch::Request, remote_ip: '198.51.100.10', user_agent: 'RSpec')
      )
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect(payment.reload.status).to eq('waiting_verification')
    expect(order.reload.status).to eq('awaiting_payment')
    expect(product.reload).to have_attributes(stock_on_hand: 3, reserved_stock: 1)
    expect(proof.reload.status).to eq('submitted')
    expect(PaymentVerificationEvent.where(payment: payment)).to be_empty
    expect(AuditLog.where(action: 'payment_approved', resource_id: payment.id.to_s)).to be_empty
  end

  describe '#storage_root' do
    let(:temp_dir) { Dir.mktmpdir('storage-root-test-') }
    let(:controller_instance) { PaymentsController.new }

    after do
      FileUtils.remove_entry(temp_dir) if temp_dir && Dir.exist?(temp_dir)
    end

    it 'returns test root when Rails.env.test? and ENV is set' do
      original_env = ENV['PAYMENT_PROOF_TEST_ROOT']
      ENV['PAYMENT_PROOF_TEST_ROOT'] = temp_dir
      result = controller_instance.send(:storage_root)
      expect(result).to eq(Pathname.new(temp_dir))
    ensure
      ENV['PAYMENT_PROOF_TEST_ROOT'] = original_env
    end

    it 'returns nil when Rails.env is not test even if ENV is set' do
      original_env = ENV['PAYMENT_PROOF_TEST_ROOT']
      ENV['PAYMENT_PROOF_TEST_ROOT'] = temp_dir
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
      result = controller_instance.send(:storage_root)
      expect(result).to be_nil
    ensure
      ENV['PAYMENT_PROOF_TEST_ROOT'] = original_env
    end

    it 'returns nil when ENV is not set' do
      original_env = ENV['PAYMENT_PROOF_TEST_ROOT']
      ENV['PAYMENT_PROOF_TEST_ROOT'] = nil
      result = controller_instance.send(:storage_root)
      expect(result).to be_nil
    ensure
      ENV['PAYMENT_PROOF_TEST_ROOT'] = original_env
    end
  end
end
