require 'rails_helper'

RSpec.describe PaymentProofCleanupJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:fixed_now) { Time.utc(2026, 11, 20, 10, 0, 0) }
  let(:cutoff) { fixed_now - 1.year }

  def create_eligible_proof(attributes = {})
    order_attrs = {
      status: attributes[:order_status] || 'completed',
      completed_at: attributes[:completed_at],
      cancelled_at: attributes[:cancelled_at]
    }.compact

    user = User.create!(
      name: "Test User #{SecureRandom.hex(4)}",
      email: "test-#{SecureRandom.hex(4)}@example.com",
      password: 'password123',
      role: 'customer'
    )

    shipping_method = ShippingMethod.create!(
      name: "Reguler-#{SecureRandom.hex(2)}",
      description: 'Regular shipping',
      estimated_days: 3,
      cost: 5000,
      is_active: true
    )

    order = Order.create!(
      order_number: "ORD-#{SecureRandom.hex(4)}",
      user: user,
      shipping_method: shipping_method,
      status: order_attrs[:status],
      subtotal: 10000,
      discount_amount: 0,
      shipping_cost: 5000,
      total_amount: 15000,
      payment_deadline_at: 12.hours.from_now,
      completed_at: order_attrs[:completed_at],
      cancelled_at: order_attrs[:cancelled_at]
    )

    payment = Payment.create!(
      order: order,
      payment_method: 'bank_transfer',
      amount: 15000,
      status: attributes[:payment_status] || 'paid'
    )

    storage_key = attributes[:storage_key] || "a1b2c3d4e5f678901234567890abcdefa1b2c3d4e5f678901234567890abcdef.jpg"

    PaymentProof.create!(
      payment: payment,
      storage_key: storage_key,
      original_filename: 'proof.jpg',
      mime_type: 'image/jpeg',
      file_size: 1024,
      status: attributes[:proof_status] || 'approved',
      uploaded_at: Time.current
    )
  end

  def create_file_on_disk(storage_key)
    path = PrivatePaymentProofStorage::ROOT.join(storage_key)
    path.dirname.mkpath
    File.binwrite(path, 'fake image content')
    path
  end

  before do
    PrivatePaymentProofStorage::ROOT.rmtree if PrivatePaymentProofStorage::ROOT.exist?
  end

  after do
    PrivatePaymentProofStorage::ROOT.rmtree if PrivatePaymentProofStorage::ROOT.exist?
  end

  describe '#perform' do
    context 'dry_run: true (default)' do
      it 'calls service with dry_run: true' do
        travel_to fixed_now
        proof = create_eligible_proof(
          payment_status: 'paid',
          order_status: 'completed',
          completed_at: cutoff - 1.day
        )
        create_file_on_disk(proof.storage_key)

        expect(PaymentProofCleanupService).to receive(:call).with(dry_run: true, cutoff: cutoff).and_call_original

        described_class.perform_now
      end

      it 'returns stats from service' do
        travel_to fixed_now
        proof = create_eligible_proof(
          payment_status: 'paid',
          order_status: 'completed',
          completed_at: cutoff - 1.day
        )
        create_file_on_disk(proof.storage_key)

        result = described_class.perform_now

        expect(result[:processed]).to eq(1)
        expect(result[:would_delete]).to eq(1)
        expect(result[:deleted]).to eq(0)
      end
    end

    context 'dry_run: false' do
      it 'calls service with dry_run: false' do
        travel_to fixed_now
        proof = create_eligible_proof(
          payment_status: 'paid',
          order_status: 'completed',
          completed_at: cutoff - 1.day
        )
        create_file_on_disk(proof.storage_key)

        expect(PaymentProofCleanupService).to receive(:call).with(dry_run: false, cutoff: cutoff).and_call_original

        described_class.perform_now(dry_run: false)
      end

      it 'returns stats with deleted count' do
        travel_to fixed_now
        proof = create_eligible_proof(
          payment_status: 'paid',
          order_status: 'completed',
          completed_at: cutoff - 1.day
        )
        create_file_on_disk(proof.storage_key)

        result = described_class.perform_now(dry_run: false)

        expect(result[:processed]).to eq(1)
        expect(result[:deleted]).to eq(1)
        expect(result[:would_delete]).to eq(0)
      end
    end

    context 'custom cutoff' do
      it 'passes custom cutoff to service' do
        custom_cutoff = fixed_now - 2.years

        expect(PaymentProofCleanupService).to receive(:call).with(dry_run: true, cutoff: custom_cutoff).and_call_original

        described_class.perform_now(cutoff: custom_cutoff)
      end
    end

    context 'integration with download endpoint' do
      it 'returns 404 for deleted file when accessing download endpoint' do
        travel_to fixed_now
        proof = create_eligible_proof(
          payment_status: 'paid',
          order_status: 'completed',
          completed_at: cutoff - 1.day
        )
        create_file_on_disk(proof.storage_key)

        described_class.perform_now(dry_run: false)

        # Verify file is deleted
        expect(File.exist?(PrivatePaymentProofStorage::ROOT.join(proof.storage_key))).to be false

        # The controller would raise ArgumentError -> 404
        expect {
          PrivatePaymentProofStorage.open(proof.storage_key)
        }.to raise_error(ArgumentError, /invalid storage/)
      end
    end

    context 'metadata preservation' do
      it 'preserves PaymentProof records after file deletion' do
        travel_to fixed_now
        proof = create_eligible_proof(
          payment_status: 'paid',
          order_status: 'completed',
          completed_at: cutoff - 1.day
        )
        create_file_on_disk(proof.storage_key)

        described_class.perform_now(dry_run: false)

        expect(PaymentProof.exists?(proof.id)).to be true
        expect(PaymentProof.find(proof.id).storage_key).to eq(proof.storage_key)
        expect(PaymentProof.find(proof.id).original_filename).to eq('proof.jpg')
      end

      it 'preserves PaymentVerificationEvent records' do
        travel_to fixed_now
        proof = create_eligible_proof(
          payment_status: 'paid',
          order_status: 'completed',
          completed_at: cutoff - 1.day
        )
        create_file_on_disk(proof.storage_key)
        admin = User.create!(
          name: 'Admin User',
          email: "admin-#{SecureRandom.hex(4)}@example.com",
          password: 'password123',
          role: 'admin'
        )
        PaymentVerificationEvent.create!(
          payment: proof.payment,
          payment_proof: proof,
          admin: admin,
          decision: 'approved',
          created_at: Time.current
        )

        described_class.perform_now(dry_run: false)

        expect(PaymentVerificationEvent.count).to eq(1)
      end

      it 'does not change Payment status' do
        travel_to fixed_now
        proof = create_eligible_proof(
          payment_status: 'paid',
          order_status: 'completed',
          completed_at: cutoff - 1.day
        )
        create_file_on_disk(proof.storage_key)

        described_class.perform_now(dry_run: false)

        expect(proof.payment.reload.status).to eq('paid')
      end

      it 'does not change Order status' do
        travel_to fixed_now
        proof = create_eligible_proof(
          payment_status: 'paid',
          order_status: 'completed',
          completed_at: cutoff - 1.day
        )
        create_file_on_disk(proof.storage_key)

        described_class.perform_now(dry_run: false)

        expect(proof.payment.order.reload.status).to eq('completed')
      end
    end
  end
end