class CartController < ApplicationController
  before_action :require_customer!

  def index
    render json: { success: true, data: serialize_cart(current_cart), message: "Keranjang berhasil diambil." }
  end

  def create_item
    product = Product.joins(:category).where(products: { is_active: true }, categories: { is_active: true }).find_by(id: params[:product_id])
    return render_error(:not_found, "PRODUCT_NOT_FOUND", "Produk aktif tidak ditemukan.") unless product

    quantity = integer_param(:quantity)
    return render_error(:unprocessable_content, "INVALID_QUANTITY", "Kuantitas harus lebih besar dari nol.") unless quantity&.positive?

    item = nil
    Product.transaction do
      product.reload
      item = current_cart.cart_items.find_or_initialize_by(product: product)
      next_quantity = item.quantity.to_i + quantity
      unless product_available?(product) && next_quantity <= available_stock(product)
        raise StockUnavailableError
      end
      item.quantity = next_quantity
      item.save!
    end

    render json: { success: true, data: serialize_cart(current_cart), message: "Produk ditambahkan ke keranjang." }, status: item.previously_new_record? ? :created : :ok
  rescue StockUnavailableError
    render_error(:unprocessable_content, "STOCK_UNAVAILABLE", "Stok produk tidak mencukupi.")
  rescue ActiveRecord::RecordInvalid => error
    render_error(:unprocessable_content, "VALIDATION_ERROR", "Item keranjang tidak valid.", error.record.errors.to_hash)
  end

  def update_item
    quantity = integer_param(:quantity)
    return render_error(:unprocessable_content, "INVALID_QUANTITY", "Kuantitas harus lebih besar dari nol.") unless quantity&.positive?

    item = current_cart.cart_items.includes(:product).find(params[:id])
    Product.transaction do
      item.product.reload
      raise StockUnavailableError unless product_available?(item.product) && quantity <= available_stock(item.product)

      item.update!(quantity: quantity)
    end
    render json: { success: true, data: serialize_cart(current_cart), message: "Kuantitas keranjang berhasil diubah." }
  rescue StockUnavailableError
    render_error(:unprocessable_content, "STOCK_UNAVAILABLE", "Stok produk tidak mencukupi.")
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "CART_ITEM_NOT_FOUND", "Item keranjang tidak ditemukan.")
  rescue ActiveRecord::RecordInvalid => error
    render_error(:unprocessable_content, "VALIDATION_ERROR", "Item keranjang tidak valid.", error.record.errors.to_hash)
  end

  def destroy_item
    item = current_cart.cart_items.find(params[:id])
    item.destroy!
    render json: { success: true, data: serialize_cart(current_cart), message: "Item keranjang dihapus." }
  rescue ActiveRecord::RecordNotFound
    render_error(:not_found, "CART_ITEM_NOT_FOUND", "Item keranjang tidak ditemukan.")
  end

  def clear
    CartItem.where(cart_id: current_cart.id).delete_all
    render json: { success: true, data: serialize_cart(current_cart), message: "Keranjang dikosongkan." }
  end

  private

  class StockUnavailableError < StandardError; end

  def current_cart
    @current_cart ||= Cart.find_or_create_by!(user: current_user)
  end

  def integer_param(name)
    value = params[name].to_s
    return nil unless value.match?(/\A\d+\z/)

    value.to_i
  end

  def product_available?(product)
    product.is_active? && product.category.is_active?
  end

  def available_stock(product)
    product.stock_on_hand - product.reserved_stock
  end

  def serialize_cart(cart)
    items = cart.cart_items.includes(product: :category).order(:id).map do |item|
      product = item.product
      {
        id: item.id, quantity: item.quantity,
        product: { id: product.id, name: product.name, slug: product.slug, sku: product.sku, price: product.price, is_active: product.is_active, category_active: product.category.is_active, available_stock: available_stock(product) },
        subtotal: product.price * item.quantity,
        available: product_available?(product) && item.quantity <= available_stock(product)
      }
    end
    { id: cart.id, items: items, subtotal: items.sum { |item| item[:subtotal] }, item_count: items.sum { |item| item[:quantity] } }
  end
end
