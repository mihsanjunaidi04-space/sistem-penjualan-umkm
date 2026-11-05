require "json"
require "securerandom"

class CheckoutService
  PAYMENT_WINDOW = 12.hours

  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message, details = {})
      @code = code
      @details = details
      super(message)
    end
  end

  def self.call(user:, shipping_method_id:, address_id:, customer_notes: nil)
    new(user:, shipping_method_id:, address_id:, customer_notes:).call
  end

  def initialize(user:, shipping_method_id:, address_id:, customer_notes:)
    @user = user
    @shipping_method_id = shipping_method_id
    @address_id = address_id
    @customer_notes = customer_notes
  end

  def call
    shipping_method = ShippingMethod.find_by(id: @shipping_method_id, is_active: true)
    raise Error.new("SHIPPING_METHOD_INVALID", "Metode pengiriman tidak tersedia.") unless shipping_method

    address = @user.addresses.find_by(id: @address_id)
    raise Error.new("ADDRESS_NOT_FOUND", "Alamat pengiriman tidak ditemukan.") unless address

    order = nil
    ActiveRecord::Base.transaction do
      cart = Cart.find_by(user_id: @user.id)
      raise Error.new("CART_EMPTY", "Keranjang masih kosong.") unless cart && cart.cart_items.exists?

      items = cart.cart_items.order(:product_id).to_a
      snapshots = reserve_products(items)
      subtotal = snapshots.sum { |snapshot| snapshot[:subtotal] }
      shipping_cost = shipping_method.cost
      now = Time.current

      order = Order.create!(
        order_number: order_number,
        user: @user,
        shipping_method: shipping_method,
        status: "awaiting_payment",
        subtotal: subtotal,
        discount_amount: 0,
        shipping_cost: shipping_cost,
        total_amount: subtotal + shipping_cost,
        recipient_name_snapshot: address.recipient_name,
        recipient_phone_snapshot: address.phone,
        shipping_address_snapshot: address_snapshot(address),
        customer_notes: @customer_notes,
        payment_deadline_at: now + PAYMENT_WINDOW
      )

      snapshots.each do |snapshot|
        OrderItem.create!(order: order, product: snapshot[:product], product_name_snapshot: snapshot[:product].name, sku_snapshot: snapshot[:product].sku, unit_price: snapshot[:price], quantity: snapshot[:quantity], subtotal: snapshot[:subtotal])
        InventoryReservation.create!(order: order, product: snapshot[:product], quantity: snapshot[:quantity], status: "reserved", expires_at: order.payment_deadline_at)
        InventoryMovement.create!(product: snapshot[:product], order: order, movement_type: "reservation", quantity: snapshot[:quantity], stock_before: snapshot[:available_before], stock_after: snapshot[:available_after], reference: order.order_number, notes: "Reservasi saat checkout", created_by: @user)
      end

      Payment.create!(order: order, payment_method: "manual_transfer", amount: order.total_amount, status: "pending")
      CartItem.where(cart_id: cart.id).delete_all
    end
    order
  end

  private

  def reserve_products(items)
    items.map do |item|
      product = Product.joins(:category).find(item.product_id)
      quantity = item.quantity.to_i
      raise Error.new("PRODUCT_UNAVAILABLE", "Produk #{product.name} tidak tersedia.") unless product.is_active? && product.category.is_active?
      raise Error.new("INVALID_QUANTITY", "Kuantitas produk tidak valid.") unless quantity.positive?

      product.reload
      available_before = product.stock_on_hand - product.reserved_stock
      updated = Product.where(id: product.id, is_active: true, category_id: product.category_id).where("stock_on_hand - reserved_stock >= ?", quantity).update_all("reserved_stock = reserved_stock + #{quantity}")
      raise Error.new("STOCK_UNAVAILABLE", "Stok produk #{product.name} tidak mencukupi.", product_id: product.id) unless updated == 1

      product.reload
      { product: product, quantity: quantity, price: product.price, subtotal: product.price * quantity, available_before: available_before, available_after: product.stock_on_hand - product.reserved_stock }
    end
  end

  def address_snapshot(address)
    JSON.generate(address.attributes.slice("recipient_name", "phone", "address_line", "province", "city", "district", "postal_code", "notes"))
  end

  def order_number
    "ORD-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(3).upcase}"
  end
end
