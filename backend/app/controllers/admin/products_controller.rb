module Admin
  class ProductsController < ApplicationController
    before_action :require_admin!

    def index
      products = Product.includes(:category).order(:name)
      products = products.where(category_id: params[:category_id]) if params[:category_id].present?
      products = products.where('name LIKE :query OR sku LIKE :query', query: "%#{sanitize_like(params[:q].to_s.strip)}%") if params[:q].present?
      render json: { success: true, data: { products: products.map { |product| ::ProductsController.serialize_product(product, request) } }, message: 'Daftar produk berhasil diambil.' }
    end

    def create
      product = Product.new(product_params)
      product.slug = slug_for(product.name) if product.slug.blank?
      save_product(product)
    end

    def update
      product = Product.find(params[:id])
      attributes = product_params
      attributes[:slug] = slug_for(attributes[:name]) if attributes[:slug].blank? && attributes[:name].present?
      if product.update(attributes)
        render json: { success: true, data: { product: ::ProductsController.serialize_product(product, request) }, message: 'Produk berhasil diubah.' }
      else
        render_error(:unprocessable_content, 'VALIDATION_ERROR', 'Data produk tidak valid.', product.errors.to_hash)
      end
    rescue ActiveRecord::RecordNotFound
      render_error(:not_found, 'PRODUCT_NOT_FOUND', 'Produk tidak ditemukan.')
    end

    def upload_image
      product = Product.find(params[:id])
      image = product.product_images.build(storage_key: ProductImageStorage.store(params[:file]), alt_text: params[:alt_text], position: params.fetch(:position, 0).to_i)
      if image.save
        render json: { success: true, data: { image: serialize_image(image, request, product.slug) }, message: 'Gambar produk berhasil diunggah.' }, status: :created
      else
        ProductImageStorage.delete(image.storage_key)
        render_error(:unprocessable_content, 'VALIDATION_ERROR', 'Data gambar tidak valid.', image.errors.to_hash)
      end
    rescue ActiveRecord::RecordNotFound
      render_error(:not_found, 'PRODUCT_NOT_FOUND', 'Produk tidak ditemukan.')
    rescue ArgumentError => error
      render_error(:unprocessable_content, 'INVALID_IMAGE', error.message)
    end

    def delete_image
      product = Product.find(params[:id])
      image = product.product_images.find(params[:image_id])
      storage_key = image.storage_key
      image.destroy!
      ProductImageStorage.delete(storage_key)
      render json: { success: true, data: {}, message: 'Gambar produk berhasil dihapus.' }
    rescue ActiveRecord::RecordNotFound
      render_error(:not_found, 'IMAGE_NOT_FOUND', 'Gambar tidak ditemukan.')
    end

    private

    def product_params
      params.permit(:category_id, :name, :slug, :sku, :description, :price, :stock_on_hand, :reserved_stock, :is_active)
    end

    def save_product(product)
      if product.save
        render json: { success: true, data: { product: ::ProductsController.serialize_product(product, request) }, message: 'Produk berhasil dibuat.' }, status: :created
      else
        render_error(:unprocessable_content, 'VALIDATION_ERROR', 'Data produk tidak valid.', product.errors.to_hash)
      end
    end

    def slug_for(value)
      value.to_s.parameterize
    end

    def sanitize_like(value)
      value.gsub(/[\\%_]/) { |character| "\\#{character}" }
    end

    def serialize_image(image, request, slug)
      ::ProductsController.serialize_product(image.product, request)[:images].find { |entry| entry[:id] == image.id }
    end
  end
end
