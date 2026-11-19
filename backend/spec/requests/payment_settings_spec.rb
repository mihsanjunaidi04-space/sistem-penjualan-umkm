require 'rails_helper'

RSpec.describe 'Admin payment settings API', type: :request do
  def user(role: 'customer', suffix: SecureRandom.hex(4))
    User.create!(name: "Settings User #{suffix}", email: "settings-#{suffix}@example.com", password: 'password123', role: role)
  end

  def headers(record)
    { 'Authorization' => "Bearer #{JwtService.encode({ user_id: record.id, role: record.role })}" }
  end

  let(:payment_keys) { %w[bank_name bank_account_name bank_account_number bank_transfer_instructions] }

  describe 'GET /admin/payment-settings' do
    it 'allows admin to access payment settings' do
      admin = user(role: 'admin')
      get '/admin/payment-settings', headers: headers(admin)
      expect(response).to have_http_status(:ok)
    end

    it 'returns all four payment keys with null values when not set' do
      admin = user(role: 'admin')
      get '/admin/payment-settings', headers: headers(admin)
      json = JSON.parse(response.body)
      expect(json['success']).to be(true)
      expect(json['data']['settings'].keys).to match_array(payment_keys)
      payment_keys.each do |key|
        expect(json['data']['settings'][key]).to be_nil
      end
    end

    it 'returns stored values when settings exist' do
      admin = user(role: 'admin')
      StoreSetting.create!(setting_key: 'bank_name', setting_value: 'Bank Test', updated_by: admin)
      StoreSetting.create!(setting_key: 'bank_account_name', setting_value: 'Test Account', updated_by: admin)
      StoreSetting.create!(setting_key: 'bank_account_number', setting_value: '1234567890', updated_by: admin)
      StoreSetting.create!(setting_key: 'bank_transfer_instructions', setting_value: 'Transfer to account above', updated_by: admin)

      get '/admin/payment-settings', headers: headers(admin)
      json = JSON.parse(response.body)
      expect(json['data']['settings']['bank_name']).to eq('Bank Test')
      expect(json['data']['settings']['bank_account_name']).to eq('Test Account')
      expect(json['data']['settings']['bank_account_number']).to eq('1234567890')
      expect(json['data']['settings']['bank_transfer_instructions']).to eq('Transfer to account above')
    end

    it 'rejects customer access with 403' do
      customer = user
      get '/admin/payment-settings', headers: headers(customer)
      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects unauthenticated access with 401' do
      get '/admin/payment-settings'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /admin/payment-settings' do
    it 'allows admin to update payment settings' do
      admin = user(role: 'admin')
      patch '/admin/payment-settings', params: {
        bank_name: 'Bank BCA',
        bank_account_name: 'Toko UMKM',
        bank_account_number: '1234567890',
        bank_transfer_instructions: 'Transfer ke rekening di atas'
      }, headers: headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be(true)
      expect(json['data']['settings']['bank_name']).to eq('Bank BCA')
      expect(json['data']['settings']['bank_account_name']).to eq('Toko UMKM')
      expect(json['data']['settings']['bank_account_number']).to eq('1234567890')
      expect(json['data']['settings']['bank_transfer_instructions']).to eq('Transfer ke rekening di atas')
    end

    it 'persists updated values in database' do
      admin = user(role: 'admin')
      patch '/admin/payment-settings', params: {
        bank_name: 'Bank Mandiri',
        bank_account_name: 'Toko Baru',
        bank_account_number: '0987654321',
        bank_transfer_instructions: 'Instruksi transfer baru'
      }, headers: headers(admin), as: :json

      expect(response).to have_http_status(:ok)

      settings = StoreSetting.where(setting_key: payment_keys).index_by(&:setting_key)
      expect(settings['bank_name'].setting_value).to eq('Bank Mandiri')
      expect(settings['bank_account_name'].setting_value).to eq('Toko Baru')
      expect(settings['bank_account_number'].setting_value).to eq('0987654321')
      expect(settings['bank_transfer_instructions'].setting_value).to eq('Instruksi transfer baru')
      expect(settings.values.map(&:updated_by).uniq).to eq([ admin ])
    end

    it 'updates only provided keys and leaves others unchanged' do
      admin = user(role: 'admin')
      StoreSetting.create!(setting_key: 'bank_name', setting_value: 'Original Bank', updated_by: admin)
      StoreSetting.create!(setting_key: 'bank_account_name', setting_value: 'Original Account', updated_by: admin)

      patch '/admin/payment-settings', params: {
        bank_name: 'Updated Bank'
      }, headers: headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['data']['settings']['bank_name']).to eq('Updated Bank')
      expect(json['data']['settings']['bank_account_name']).to eq('Original Account')
      expect(json['data']['settings']['bank_account_number']).to be_nil
      expect(json['data']['settings']['bank_transfer_instructions']).to be_nil
    end

    it 'ignores parameters outside the four payment keys' do
      admin = user(role: 'admin')
      StoreSetting.create!(setting_key: 'other_setting', setting_value: 'original', updated_by: admin)

      patch '/admin/payment-settings', params: {
        bank_name: 'Bank Test',
        other_setting: 'should not change',
        random_key: 'ignored'
      }, headers: headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(StoreSetting.find_by(setting_key: 'other_setting').setting_value).to eq('original')
      expect(StoreSetting.find_by(setting_key: 'random_key')).to be_nil
    end

    it 'rejects customer update with 403' do
      customer = user
      patch '/admin/payment-settings', params: { bank_name: 'Bank Test' }, headers: headers(customer), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects unauthenticated update with 401' do
      patch '/admin/payment-settings', params: { bank_name: 'Bank Test' }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects empty string values with validation error' do
      admin = user(role: 'admin')
      patch '/admin/payment-settings', params: {
        bank_name: '',
        bank_account_name: '',
        bank_account_number: '',
        bank_transfer_instructions: ''
      }, headers: headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json['success']).to be(false)
      expect(json['error']['code']).to eq('VALIDATION_ERROR')
    end

    it 'strips whitespace from values' do
      admin = user(role: 'admin')
      patch '/admin/payment-settings', params: {
        bank_name: '  Bank BCA  ',
        bank_account_name: '  Toko UMKM  ',
        bank_account_number: '  1234567890  ',
        bank_transfer_instructions: '  Transfer ke rekening  '
      }, headers: headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['data']['settings']['bank_name']).to eq('Bank BCA')
      expect(json['data']['settings']['bank_account_name']).to eq('Toko UMKM')
      expect(json['data']['settings']['bank_account_number']).to eq('1234567890')
      expect(json['data']['settings']['bank_transfer_instructions']).to eq('Transfer ke rekening')
    end

    it 'validates presence of setting_value at model level' do
      admin = user(role: 'admin')
      # StoreSetting validates presence of setting_value, but controller uses .to_s.strip
      # which produces empty string - model validation should reject this
      # The controller rescues RecordInvalid and returns 422
      # However, the controller's permitted params are all optional, so we test
      # that providing nil for a required key is handled

      # Test that StoreSetting model validation works
      setting = StoreSetting.new(setting_key: 'bank_name', setting_value: '')
      expect(setting).not_to be_valid
      expect(setting.errors[:setting_value]).to include("can't be blank")
    end
  end
end
 
 
