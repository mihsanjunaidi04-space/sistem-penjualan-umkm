require 'rails_helper'

RSpec.describe AuditLog, type: :model do
  let(:attributes) do
    {
      action: 'payment_approved',
      resource_type: 'Payment',
      resource_id: 'payment-1',
      metadata: { order_id: 1 }.to_json
    }
  end

  it 'allows a new audit log to be created' do
    audit_log = described_class.create!(attributes)

    expect(audit_log).to be_persisted
    expect(described_class.find(audit_log.id)).to have_attributes(
      action: 'payment_approved',
      resource_type: 'Payment',
      resource_id: 'payment-1',
      metadata: { order_id: 1 }.to_json
    )
  end

  it 'rejects update without changing the stored record' do
    audit_log = described_class.create!(attributes)

    expect { audit_log.update(action: 'tampered') }.to raise_error(ActiveRecord::ReadOnlyRecord)

    expect(audit_log.reload.action).to eq('payment_approved')
  end

  it 'rejects update! without changing the stored record' do
    audit_log = described_class.create!(attributes)

    expect { audit_log.update!(action: 'tampered') }.to raise_error(ActiveRecord::ReadOnlyRecord)

    expect(audit_log.reload.action).to eq('payment_approved')
  end

  it 'rejects destroy without deleting the stored record' do
    audit_log = described_class.create!(attributes)

    expect { audit_log.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)

    expect(described_class.exists?(audit_log.id)).to be(true)
  end

  it 'rejects destroy! without deleting the stored record' do
    audit_log = described_class.create!(attributes)

    expect { audit_log.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)

    expect(described_class.exists?(audit_log.id)).to be(true)
  end

  it 'rejects delete without deleting the stored record' do
    audit_log = described_class.create!(attributes)

    expect { audit_log.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)

    expect(described_class.exists?(audit_log.id)).to be(true)
    expect(audit_log.reload.action).to eq('payment_approved')
  end
end
