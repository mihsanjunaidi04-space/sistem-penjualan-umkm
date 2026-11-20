require 'rails_helper'

RSpec.describe DataRetentionCleanupJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  describe '#perform' do
    let(:fixed_now) { Time.utc(2026, 11, 20, 10, 0, 0) }
    let(:cutoff_90_days_ago) { fixed_now - 90.days }

    it 'uses 90 days ago as default cutoff when called without arguments' do
      expect(DataRetentionCleanupService).to receive(:anonymize_ip_user_agent!).with(before: cutoff_90_days_ago)
      travel_to(fixed_now) do
        described_class.perform_now
      end
    end

    it 'anonymizes audit log records older than 90 days when called without arguments' do
      travel_to(fixed_now) do
        old_record = AuditLog.create!(
          action: 'payment_approved',
          resource_type: 'Payment',
          resource_id: 'payment-old',
          ip_address: '10.0.0.1',
          user_agent: 'TestAgent',
          created_at: cutoff_90_days_ago - 1.day,
          updated_at: fixed_now
        )

        described_class.perform_now

        expect(old_record.reload.ip_address).to be_nil
        expect(old_record.reload.user_agent).to be_nil
      end
    end

    it 'anonymizes audit log records exactly at 90 days boundary when called without arguments' do
      travel_to(fixed_now) do
        boundary_record = AuditLog.create!(
          action: 'payment_approved',
          resource_type: 'Payment',
          resource_id: 'payment-boundary',
          ip_address: '10.0.0.2',
          user_agent: 'TestAgent',
          created_at: cutoff_90_days_ago,
          updated_at: fixed_now
        )

        described_class.perform_now

        expect(boundary_record.reload.ip_address).to be_nil
        expect(boundary_record.reload.user_agent).to be_nil
      end
    end

    it 'does not anonymize audit log records younger than 90 days when called without arguments' do
      travel_to(fixed_now) do
        recent_record = AuditLog.create!(
          action: 'payment_approved',
          resource_type: 'Payment',
          resource_id: 'payment-recent',
          ip_address: '10.0.0.3',
          user_agent: 'TestAgent',
          created_at: cutoff_90_days_ago + 1.day,
          updated_at: fixed_now
        )

        described_class.perform_now

        expect(recent_record.reload.ip_address).to eq('10.0.0.3')
        expect(recent_record.reload.user_agent).to eq('TestAgent')
      end
    end

    it 'passes explicit before parameter to service' do
      explicit_cutoff = Time.utc(2026, 1, 1, 0, 0, 0)
      expect(DataRetentionCleanupService).to receive(:anonymize_ip_user_agent!).with(before: explicit_cutoff)
      described_class.perform_now(before: explicit_cutoff)
    end

    it 'processes at most 100 records per call when called without arguments' do
      travel_to(fixed_now) do
        150.times do |i|
          AuditLog.create!(
            action: 'payment_approved',
            resource_type: 'Payment',
            resource_id: "payment-batch-#{i}",
            ip_address: '10.0.0.4',
            user_agent: 'TestAgent',
            created_at: cutoff_90_days_ago - 1.day,
            updated_at: fixed_now
          )
        end

        described_class.perform_now

        expect(AuditLog.where(ip_address: nil, user_agent: nil).count).to eq(100)
        expect(AuditLog.where.not(ip_address: nil).or(AuditLog.where.not(user_agent: nil)).count).to eq(50)
      end
    end

    it 'does not enable scheduler or Solid Queue' do
      travel_to(fixed_now) do
        AuditLog.create!(
          action: 'payment_approved',
          resource_type: 'Payment',
          resource_id: 'payment-no-scheduler',
          ip_address: '10.0.0.5',
          user_agent: 'TestAgent',
          created_at: cutoff_90_days_ago - 1.day,
          updated_at: fixed_now
        )

        expect { described_class.perform_now }.not_to raise_error
        expect(AuditLog.where(ip_address: nil, user_agent: nil).count).to eq(1)
      end
    end
  end
end
