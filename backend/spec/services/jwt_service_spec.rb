require 'rails_helper'

RSpec.describe JwtService do
  around do |example|
    original_env = ENV['JWT_SECRET']
    example.run
  ensure
    ENV['JWT_SECRET'] = original_env
  end

  it 'uses Rails credentials when the production environment variable is blank' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
    allow(Rails.application.credentials).to receive(:dig).with(:jwt, :secret).and_return('c' * 32)
    ENV['JWT_SECRET'] = '  '

    expect(described_class.secret_key).to eq('c' * 32)
  end

  it 'accepts a production secret of at least 32 bytes and rejects missing or shorter values' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
    allow(Rails.application.credentials).to receive(:dig).with(:jwt, :secret).and_return(nil)

    ENV['JWT_SECRET'] = 's' * 32
    expect(described_class.secret_key).to eq('s' * 32)

    ENV['JWT_SECRET'] = 's' * 31
    expect { described_class.secret_key }.to raise_error(ArgumentError, /at least 32 bytes/)

    ENV['JWT_SECRET'] = ''
    expect { described_class.secret_key }.to raise_error(ArgumentError, /JWT_SECRET or Rails credentials/)
  end

  it 'does not use JWT_SECRET in development or test and returns a stable local signing secret' do
    %w[development test].each do |environment|
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new(environment))
      ENV['JWT_SECRET'] = 'production-secret-that-must-not-be-used'

      secret = described_class.secret_key
      expect(secret).not_to eq(ENV['JWT_SECRET'])
      expect(described_class.secret_key).to eq(secret)
    end
  end

  it 'preserves JWT encoding and decoding' do
    ENV.delete('JWT_SECRET')
    token = described_class.encode(user_id: 42, role: 'customer')
    claims = described_class.decode(token)

    expect(claims[:user_id]).to eq(42)
    expect(claims[:role]).to eq('customer')
    expect(claims[:jti]).to be_present
    expect(claims[:exp]).to be_present
  end

  it 'continues to revoke and identify revoked tokens' do
    token = described_class.encode(user_id: 42)
    claims = described_class.decode(token)

    described_class.revoke(token, claims)

    expect(described_class.revoked?(claims)).to be(true)
  end
end
