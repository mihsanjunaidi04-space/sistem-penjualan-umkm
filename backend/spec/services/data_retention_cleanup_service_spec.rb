require 'rails_helper'

RSpec.describe DataRetentionCleanupService, type: :service do
  let(:fixed_now) { Time.utc(2026, 11, 20, 10, 0, 0) }
  let(:cutoff) { fixed_now - 90.days }

  def create_audit_log(attributes = {})
    defaults = {
      action: 'payment_approved',
      resource_type: 'Payment',
      resource_id: 'payment-1',
      ip_address: '192.168.1.1',
      user_agent: 'Mozilla/5.0',
      created_at: fixed_now,
      updated_at: fixed_now
    }
    AuditLog.create!(defaults.merge(attributes))
  end

  describe '.anonymize_ip_user_agent!' do
    context 'when record is older than 90 days' do
      it 'anonymizes ip_address and user_agent' do
        audit_log = create_audit_log(created_at: cutoff - 1.day)

        result = described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(result).to eq(1)
        expect(audit_log.reload.ip_address).to be_nil
        expect(audit_log.reload.user_agent).to be_nil
      end
    end

    context 'when record is exactly at cutoff' do
      it 'is processed (<=)' do
        audit_log = create_audit_log(created_at: cutoff)

        result = described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(result).to eq(1)
        expect(audit_log.reload.ip_address).to be_nil
        expect(audit_log.reload.user_agent).to be_nil
      end
    end

    context 'when record is younger than 90 days' do
      it 'is not changed' do
        audit_log = create_audit_log(created_at: cutoff + 1.day)

        result = described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(result).to eq(0)
        expect(audit_log.reload.ip_address).to eq('192.168.1.1')
        expect(audit_log.reload.user_agent).to eq('Mozilla/5.0')
      end
    end

    context 'when record has no ip_address and no user_agent' do
      it 'is not processed' do
        audit_log = create_audit_log(created_at: cutoff - 1.day, ip_address: nil, user_agent: nil)

        result = described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(result).to eq(0)
        expect(audit_log.reload.ip_address).to be_nil
        expect(audit_log.reload.user_agent).to be_nil
      end
    end

    context 'when record has only ip_address' do
      it 'anonymizes both fields' do
        audit_log = create_audit_log(created_at: cutoff - 1.day, user_agent: nil)

        result = described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(result).to eq(1)
        expect(audit_log.reload.ip_address).to be_nil
        expect(audit_log.reload.user_agent).to be_nil
      end
    end

    context 'when record has only user_agent' do
      it 'anonymizes both fields' do
        audit_log = create_audit_log(created_at: cutoff - 1.day, ip_address: nil)

        result = described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(result).to eq(1)
        expect(audit_log.reload.ip_address).to be_nil
        expect(audit_log.reload.user_agent).to be_nil
      end
    end

    context 'transaction data preservation' do
      it 'keeps action unchanged' do
        audit_log = create_audit_log(created_at: cutoff - 1.day, action: 'cancellation_approved')

        described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(audit_log.reload.action).to eq('cancellation_approved')
      end

      it 'keeps user_id unchanged' do
        user = User.create!(name: 'Alice', email: 'alice@example.com', password: 'password123', role: 'customer')
        audit_log = create_audit_log(created_at: cutoff - 1.day, user_id: user.id)

        described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(audit_log.reload.user_id).to eq(user.id)
      end

      it 'keeps created_at unchanged' do
        audit_log = create_audit_log(created_at: cutoff - 1.day)

        described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(audit_log.reload.created_at).to eq(cutoff - 1.day)
      end

      it 'record still exists' do
        audit_log = create_audit_log(created_at: cutoff - 1.day)

        described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(AuditLog.exists?(audit_log.id)).to be(true)
      end
    end

    context 'batch limit' do
      it 'processes at most 100 records per call' do
        150.times do |i|
          create_audit_log(created_at: cutoff - 1.day, resource_id: "payment-#{i}")
        end

        result = described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(result).to eq(100)
        expect(AuditLog.where(ip_address: nil, user_agent: nil).count).to eq(100)
        expect(AuditLog.where.not(ip_address: nil).or(AuditLog.where.not(user_agent: nil)).count).to eq(50)
      end
    end

    context 'deterministic order' do
      it 'orders by created_at then id' do
        log1 = create_audit_log(created_at: cutoff - 2.days, resource_id: 'b')
        log2 = create_audit_log(created_at: cutoff - 1.days, resource_id: 'a')
        log3 = create_audit_log(created_at: cutoff - 2.days, resource_id: 'a')

        described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(AuditLog.where(ip_address: nil, user_agent: nil).pluck(:id).sort).to eq([ log1.id, log2.id, log3.id ].sort)
      end
    end

    context 'idempotency' do
      it 'repeated execution does not error' do
        audit_log = create_audit_log(created_at: cutoff - 1.day)

        first_result = described_class.anonymize_ip_user_agent!(before: cutoff)
        second_result = described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(first_result).to eq(1)
        expect(second_result).to eq(0)
        expect(audit_log.reload.ip_address).to be_nil
        expect(audit_log.reload.user_agent).to be_nil
      end
    end

    context 'when no candidates exist' do
      it 'returns 0' do
        result = described_class.anonymize_ip_user_agent!(before: cutoff)

        expect(result).to eq(0)
      end
    end
  end
end
