class AdminProductUpdateService
  class StockConflict < StandardError; end

  def self.call(product:, attributes:, admin:)
    new(product:, attributes:, admin:).call
  end

  def initialize(product:, attributes:, admin:)
    @product = product
    @attributes = attributes
    @admin = admin
  end

  def call
    Product.transaction do
      @product.reload
      previous_stock = @product.stock_on_hand
      stock_requested = @attributes.key?(:stock_on_hand)
      requested_stock = @attributes.delete(:stock_on_hand)

      @product.assign_attributes(@attributes)
      @product.stock_on_hand = requested_stock if stock_requested
      raise ActiveRecord::RecordInvalid, @product unless @product.valid?
      requested_stock = @product.stock_on_hand if stock_requested

      if stock_requested && requested_stock != previous_stock
        update_stock!(previous_stock, requested_stock)
        @product.reload
        @product.assign_attributes(@attributes)
        @product.save!
        create_movement(previous_stock, requested_stock)
      else
        @product.save!
      end
      @product
    end
  end

  private

  def update_stock!(previous_stock, requested_stock)
    updated = Product.where(id: @product.id, stock_on_hand: previous_stock)
                     .where("reserved_stock <= ?", requested_stock)
                     .update_all([ "stock_on_hand = ?, updated_at = ?", requested_stock, Time.current ])
    raise StockConflict unless updated == 1
  rescue ActiveRecord::StatementInvalid => error
    raise unless error.cause.is_a?(SQLite3::BusyException)

    raise StockConflict
  end

  def create_movement(previous_stock, requested_stock)
    delta = requested_stock - previous_stock
    InventoryMovement.create!(
      product: @product,
      movement_type: delta.positive? ? "stock_in" : "stock_out",
      quantity: delta,
      stock_before: previous_stock,
      stock_after: requested_stock,
      created_by: @admin
    )
  end
end
