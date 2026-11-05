require 'rails_helper'
require 'tempfile'

RSpec.describe 'Product catalog API', type: :request do
  def auth_headers(user)
    { 'Authorization' => "Bearer #{JwtService.encode({ user_id: user.id, role: user.role })}" }
  end

  def admin
    @admin ||= User.create!(name: 'Catalog Admin', email: 'catalog-admin@example.com', password: 'password123', role: 'admin')
  end

  def customer
    @customer ||= User.create!(name: 'Catalog Customer', email: 'catalog-customer@example.com', password: 'password123', role: 'customer')
  end

  def category(attributes = {})
    Category.create!({ name: 'Makanan', slug: 'makanan', description: 'Produk makanan' }.merge(attributes))
  end

  def product(category_record, attributes = {})
    Product.create!({ category: category_record, name: 'Keripik Singkong', slug: 'keripik-singkong', sku: 'KS-001', price: 15000, stock_on_hand: 10, reserved_stock: 2, is_active: true }.merge(attributes))
  end

  describe 'public catalog' do
    it 'lists only active categories and products, with search and category filter' do
      active_category = category
      inactive_category = category(name: 'Rahasia', slug: 'rahasia', is_active: false)
      product(active_category)
      product(active_category, name: 'Teh Botol', slug: 'teh-botol', sku: 'TB-001')
      product(inactive_category, name: 'Tidak Tampil', slug: 'tidak-tampil', sku: 'NT-001')
      Product.create!(category: active_category, name: 'Nonaktif', slug: 'nonaktif', sku: 'NA-001', price: 1000, is_active: false)

      get '/categories'
      expect(response).to have_http_status(:ok)
      category_slugs = JSON.parse(response.body).dig('data', 'categories').map { |item| item['slug'] }
      expect(category_slugs).to include('makanan')
      expect(category_slugs).not_to include('rahasia')

      get '/products', params: { q: 'teh', category: 'makanan' }
      json = JSON.parse(response.body)
      expect(json['data']['products'].map { |item| item['slug'] }).to eq(['teh-botol'])
      expect(json['data']['products'].first['data']).to be_nil
      expect(json['data']['products'].first['available_stock']).to eq(8)
    end

    it 'does not expose inactive product or category detail' do
      inactive_category = category(is_active: false)
      inactive_product = product(inactive_category, is_active: false)

      get "/products/#{inactive_product.slug}"
      expect(response).to have_http_status(:not_found)

      get "/categories/#{inactive_category.slug}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'admin catalog' do
    it 'rejects customer and unauthenticated admin requests' do
      post '/admin/categories', params: { name: 'Minuman' }, as: :json
      expect(response).to have_http_status(:unauthorized)

      post '/admin/categories', params: { name: 'Minuman' }, headers: auth_headers(customer), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'creates and updates categories with validation' do
      post '/admin/categories', params: { name: 'Minuman', description: 'Segar', is_active: true }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:created)
      category_id = JSON.parse(response.body).dig('data', 'category', 'id')

      patch "/admin/categories/#{category_id}", params: { name: '' }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      patch "/admin/categories/#{category_id}", params: { is_active: false }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig('data', 'category', 'is_active')).to be(false)
    end

    it 'creates, updates, filters, and validates products' do
      category_record = category
      post '/admin/products', params: { category_id: category_record.id, name: 'Kopi', sku: 'KP-001', price: 25000, stock_on_hand: 5, reserved_stock: 0, is_active: true }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:created)
      product_id = JSON.parse(response.body).dig('data', 'product', 'id')

      post '/admin/products', params: { category_id: 999_999, name: 'Invalid', sku: 'INV-001', price: -1, stock_on_hand: 1, reserved_stock: 0 }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      get '/admin/products', params: { category_id: category_record.id, q: 'kopi' }, headers: auth_headers(admin)
      expect(JSON.parse(response.body).dig('data', 'products').length).to eq(1)

      patch "/admin/products/#{product_id}", params: { stock_on_hand: 2, reserved_stock: 3 }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      patch "/admin/products/#{product_id}", params: { is_active: false }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:ok)
      get '/products', params: { q: 'kopi' }
      expect(JSON.parse(response.body).dig('data', 'products')).to be_empty
    end

    it 'uploads and removes an allowed product image' do
      product_record = product(category)
      file = Tempfile.new(['catalog', '.png'])
      file.write('fake png bytes')
      file.rewind

      post "/admin/products/#{product_record.id}/images", params: { file: Rack::Test::UploadedFile.new(file.path, 'image/png'), alt_text: 'Keripik' }, headers: auth_headers(admin)
      expect(response).to have_http_status(:created)
      image_id = JSON.parse(response.body).dig('data', 'image', 'id')

      delete "/admin/products/#{product_record.id}/images/#{image_id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)

      invalid_file = Tempfile.new(['catalog', '.txt'])
      invalid_file.write('not an image')
      invalid_file.rewind
      post "/admin/products/#{product_record.id}/images", params: { file: Rack::Test::UploadedFile.new(invalid_file.path, 'image/png') }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      invalid_file.close
      invalid_file.unlink
    ensure
      file&.close
      file&.unlink
    end
  end
end
