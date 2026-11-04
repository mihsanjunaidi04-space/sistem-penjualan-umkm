require 'rails_helper'

RSpec.describe 'Health Check', type: :request do
  describe 'GET /health' do
    it 'returns 200 OK with success response' do
      get '/health'

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
    end

    it 'returns correct JSON envelope' do
      get '/health'

      json = JSON.parse(response.body)
      expect(json['success']).to eq(true)
      expect(json['data']).to be_a(Hash)
      expect(json['data']['status']).to eq('ok')
      expect(json['message']).to eq('Health check passed')
    end

    it 'does not expose internal information' do
      get '/health'

      json = JSON.parse(response.body)
      expect(json.to_s).not_to include('stack', 'trace', 'version', 'Rails')
    end
  end
end
