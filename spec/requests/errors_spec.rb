require 'rails_helper'

RSpec.describe 'Error Handling', type: :request do
  describe 'GET /undefined-route' do
    it 'returns 404 Not Found' do
      get '/undefined-route'

      expect(response).to have_http_status(:not_found)
      expect(response.content_type).to include('application/json')
    end

    it 'returns correct error envelope' do
      get '/undefined-route'

      json = JSON.parse(response.body)
      expect(json['success']).to eq(false)
      expect(json['error']).to be_a(Hash)
      expect(json['error']['code']).to eq('NOT_FOUND')
      expect(json['error']['message']).to eq('Endpoint not found')
    end

    it 'does not expose stack trace or internal details' do
      get '/undefined-route'

      response_body = response.body
      expect(response_body).not_to include('stack', 'trace', 'SQL', '/')
    end
  end

  describe 'Health check route still works' do
    it 'GET /health is not caught by catch-all' do
      get '/health'

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to eq(true)
    end
  end
end
