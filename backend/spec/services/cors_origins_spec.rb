require 'rails_helper'

RSpec.describe CorsOrigins do
  it 'compiles the DNS label pattern and accepts one-character labels only without edge hyphens' do
    pattern = described_class::DNS_LABEL_PATTERN

    expect(pattern.match?('x')).to be(true)
    expect(pattern.match?('valid-label')).to be(true)
    expect(pattern.match?('-invalid')).to be(false)
    expect(pattern.match?('invalid-')).to be(false)
  end

  it 'allows the local frontend origin in development and test configuration' do
    response = Rack::MockRequest.new(Rails.application).options('/health',
      'HTTP_ORIGIN' => 'http://localhost:5173',
      'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'GET')

    expect(response.headers['access-control-allow-origin']).to eq('http://localhost:5173')
  end

  it 'does not allow an unregistered origin' do
    response = Rack::MockRequest.new(Rails.application).options('/health',
      'HTTP_ORIGIN' => 'https://attacker.example',
      'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'GET')

    expect(response.headers).not_to have_key('access-control-allow-origin')
  end

  it 'returns an allow-origin header for a registered production origin' do
    response = production_cors_response('https://shop.example.com', 'https://shop.example.com')

    expect(response.headers['access-control-allow-origin']).to eq('https://shop.example.com')
  end

  it 'does not return an allow-origin header for an unregistered production origin' do
    response = production_cors_response('https://shop.example.com', 'https://other.example.com')

    expect(response.headers).not_to have_key('access-control-allow-origin')
  end

  it 'accepts valid DNS hostnames and multiple origins while trimming whitespace and duplicates' do
    expect(described_class.production(' https://shop.example.com , https://admin.example.co.uk,https://shop.example.com ')).to eq(
      [ 'https://shop.example.com', 'https://admin.example.co.uk' ]
    )
  end

  it 'rejects hostnames with labels that begin or end with a hyphen' do
    [ 'https://-shop.example.com', 'https://shop-.example.com', 'https://shop.-example.com', 'https://shop.example-.com' ].each do |origin|
      expect { described_class.production(origin) }.to raise_error(ArgumentError)
    end
  end

  it 'rejects invalid ports' do
    [ 'https://shop.example.com:0', 'https://shop.example.com:65536', 'https://shop.example.com:abc' ].each do |origin|
      expect { described_class.production(origin) }.to raise_error(ArgumentError)
    end
  end

  it 'rejects paths, queries, fragments, and userinfo' do
    [
      'https://shop.example.com/path',
      'https://shop.example.com?query=1',
      'https://shop.example.com#fragment',
      'https://user@shop.example.com'
    ].each do |origin|
      expect { described_class.production(origin) }.to raise_error(ArgumentError)
    end
  end

  it 'rejects wildcard, HTTP, malformed hostnames, and empty production configuration' do
    [
      '*', 'https://*.example.com', 'https://shop.example.com,*',
      'http://shop.example.com', 'https://shop..example.com',
      'https://', '', '  ', 'https://shop.example.com,,https://admin.example.com'
    ].each do |value|
      expect { described_class.production(value) }.to raise_error(ArgumentError)
    end
  end

  def production_cors_response(allowed_origin, request_origin)
    origins = described_class.production(allowed_origin)
    middleware = Rack::Cors.new(->(_env) { [ 200, { 'Content-Type' => 'text/plain' }, [ 'ok' ] ] }) do
      allow do
        origins(*origins)
        resource '*', headers: :any, methods: [ :get, :options ], credentials: false
      end
    end

    Rack::MockRequest.new(middleware).options('/',
      'HTTP_ORIGIN' => request_origin,
      'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'GET')
  end
end
