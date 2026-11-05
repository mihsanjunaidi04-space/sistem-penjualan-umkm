class ProductsController < ApplicationController
  MAX_PAGE_SIZE = 50

  def index
    products = Product.joins(:category).where(products: { is_active: true }, categories: { is_active: true })
    products = products.where('products.name LIKE :query OR products.sku LIKE :query', query: "%#{sanitize_like(params[:q].to_s.strip)}%") if params[:q].present?
    products = products.where(categories: { slug: params[:category] }) if params[:category].present?
    products = products.order(:name)
    render json: { success: true, data: paginate(products), message: 'Daftar produk berhasil diambil.' }
  end

  def show
    product = Product.joins(:category).where(products: { is_active: true }, categories: { is_active: true }).find_by!(slug: params[:slug])
    render json: { success: true, data: { product: self.class.serialize_product(product, request) }, message: 'Detail produk berhasil diambil.' }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, 'PRODUCT_NOT_FOUND', 'Produk tidak ditemukan.')
  end

  def image
    product = Product.joins(:category).where(products: { is_active: true }, categories: { is_active: true }).find_by!(slug: params[:slug])
    image = product.product_images.find(params[:image_id])
    path = ProductImageStorage.path(image.storage_key)
    return render_error(:not_found, 'IMAGE_NOT_FOUND', 'Gambar tidak ditemukan.') unless path

    send_file path, type: image_content_type(path), disposition: 'inline', filename: File.basename(path)
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, 'IMAGE_NOT_FOUND', 'Gambar tidak ditemukan.')
  end

  def self.serialize_product(product, request)
    {
      id: product.id, name: product.name, slug: product.slug, sku: product.sku,
      description: product.description, price: product.price,
      stock_on_hand: product.stock_on_hand, reserved_stock: product.reserved_stock,
      available_stock: product.stock_on_hand - product.reserved_stock,
      is_active: product.is_active,
      category: { id: product.category.id, name: product.category.name, slug: product.category.slug },
      images: product.product_images.order(:position, :id).map { |image| serialize_image(image, request, product.slug) }
    }
  end

  def self.serialize_image(image, request, slug)
    { id: image.id, alt_text: image.alt_text, position: image.position, url: "#{request.base_url}/products/#{slug}/images/#{image.id}" }
  end

  private

  def paginate(scope)
    page = [params.fetch(:page, 1).to_i, 1].max
    per_page = [[params.fetch(:per_page, 12).to_i, 1].max, MAX_PAGE_SIZE].min
    total = scope.count
    products = scope.offset((page - 1) * per_page).limit(per_page)
    { products: products.map { |product| self.class.serialize_product(product, request) }, pagination: { page: page, per_page: per_page, total: total, total_pages: (total.to_f / per_page).ceil } }
  end

  def sanitize_like(value)
    value.gsub(/[\\%_]/) { |character| "\\#{character}" }
  end

  def image_content_type(path)
    { '.jpg' => 'image/jpeg', '.jpeg' => 'image/jpeg', '.png' => 'image/png', '.webp' => 'image/webp' }[File.extname(path).downcase] || 'application/octet-stream'
  end
end
