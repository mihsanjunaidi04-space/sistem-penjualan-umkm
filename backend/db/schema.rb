# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026110600001) do
  create_table "addresses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "recipient_name", limit: 150, null: false
    t.string "phone", limit: 30, null: false
    t.text "address_line", null: false
    t.string "province", limit: 120, null: false
    t.string "city", limit: 120, null: false
    t.string "district", limit: 120, null: false
    t.string "postal_code", limit: 20, null: false
    t.text "notes"
    t.boolean "is_default", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_addresses_on_user_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.bigint "user_id"
    t.string "action", limit: 120, null: false
    t.string "resource_type", limit: 80, null: false
    t.string "resource_id", limit: 120
    t.string "ip_address", limit: 45
    t.text "user_agent"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["resource_type"], name: "index_audit_logs_on_resource_type"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "cancellation_requests", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "requested_by", null: false
    t.text "reason", null: false
    t.string "status", limit: 20, default: "pending", null: false
    t.bigint "reviewed_by"
    t.datetime "reviewed_at"
    t.text "admin_note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_cancellation_requests_on_order_id"
    t.index ["requested_by"], name: "index_cancellation_requests_on_requested_by"
    t.index ["reviewed_by"], name: "index_cancellation_requests_on_reviewed_by"
    t.index ["status"], name: "index_cancellation_requests_on_status"
    t.check_constraint "status IN ('pending', 'approved', 'rejected')", name: "cancellation_requests_status_check"
  end

  create_table "cart_items", force: :cascade do |t|
    t.bigint "cart_id", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cart_id", "product_id"], name: "index_cart_items_on_cart_id_and_product_id", unique: true
    t.index ["cart_id"], name: "index_cart_items_on_cart_id"
    t.index ["product_id"], name: "index_cart_items_on_product_id"
    t.check_constraint "quantity > 0", name: "cart_items_quantity_positive"
  end

  create_table "carts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_carts_on_user_id", unique: true
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", limit: 150, null: false
    t.string "slug", limit: 120, null: false
    t.text "description"
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "idempotency_keys", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "key", limit: 180, null: false
    t.string "request_hash", null: false
    t.integer "response_status", default: 200, null: false
    t.text "response_body"
    t.string "resource_type", limit: 80
    t.string "resource_id", limit: 120
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_idempotency_keys_on_expires_at"
    t.index ["user_id", "key"], name: "index_idempotency_keys_on_user_id_and_key", unique: true
    t.index ["user_id"], name: "index_idempotency_keys_on_user_id"
    t.check_constraint "response_status >= 100", name: "idempotency_keys_response_status_minimum"
  end

  create_table "inventory_movements", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "order_id"
    t.string "movement_type", limit: 40, null: false
    t.integer "quantity", null: false
    t.integer "stock_before", null: false
    t.integer "stock_after", null: false
    t.string "reference", limit: 120
    t.text "notes"
    t.bigint "created_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by"], name: "index_inventory_movements_on_created_by"
    t.index ["order_id"], name: "index_inventory_movements_on_order_id"
    t.index ["product_id"], name: "index_inventory_movements_on_product_id"
    t.check_constraint "movement_type IN ('stock_in', 'stock_out', 'reservation', 'reservation_release', 'reservation_conversion', 'adjustment', 'return')", name: "inventory_movements_type_check"
    t.check_constraint "quantity != 0", name: "inventory_movements_quantity_non_zero"
  end

  create_table "inventory_reservations", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", null: false
    t.string "status", limit: 30, default: "reserved", null: false
    t.datetime "expires_at"
    t.datetime "converted_at"
    t.datetime "released_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_inventory_reservations_on_expires_at"
    t.index ["order_id", "product_id"], name: "index_inventory_reservations_on_order_id_and_product_id", unique: true
    t.index ["order_id"], name: "index_inventory_reservations_on_order_id"
    t.index ["product_id"], name: "index_inventory_reservations_on_product_id"
    t.index ["status"], name: "index_inventory_reservations_on_status"
    t.check_constraint "quantity > 0", name: "inventory_reservations_quantity_positive"
    t.check_constraint "status IN ('reserved', 'converted', 'released')", name: "inventory_reservations_status_check"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "type", limit: 50, null: false
    t.string "title", limit: 180, null: false
    t.text "message", null: false
    t.text "data"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["read_at"], name: "index_notifications_on_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "product_id", null: false
    t.string "product_name_snapshot", limit: 180, null: false
    t.string "sku_snapshot", limit: 120, null: false
    t.integer "unit_price", null: false
    t.integer "quantity", null: false
    t.integer "subtotal", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
    t.check_constraint "quantity > 0", name: "order_items_quantity_positive"
    t.check_constraint "subtotal >= 0", name: "order_items_subtotal_non_negative"
    t.check_constraint "unit_price >= 0", name: "order_items_unit_price_non_negative"
  end

  create_table "orders", force: :cascade do |t|
    t.string "order_number", limit: 80, null: false
    t.bigint "user_id", null: false
    t.bigint "shipping_method_id", null: false
    t.string "status", limit: 30, default: "awaiting_payment", null: false
    t.integer "subtotal", default: 0, null: false
    t.integer "discount_amount", default: 0, null: false
    t.integer "shipping_cost", default: 0, null: false
    t.integer "total_amount", default: 0, null: false
    t.string "voucher_code_snapshot", limit: 80
    t.string "recipient_name_snapshot", limit: 150
    t.string "recipient_phone_snapshot", limit: 30
    t.text "shipping_address_snapshot"
    t.text "customer_notes"
    t.datetime "payment_deadline_at", null: false
    t.datetime "shipped_at"
    t.datetime "completed_at"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_orders_on_created_at"
    t.index ["order_number"], name: "index_orders_on_order_number", unique: true
    t.index ["shipping_method_id"], name: "index_orders_on_shipping_method_id"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["user_id"], name: "index_orders_on_user_id"
    t.check_constraint "discount_amount >= 0", name: "orders_discount_amount_non_negative"
    t.check_constraint "shipping_cost >= 0", name: "orders_shipping_cost_non_negative"
    t.check_constraint "status IN ('awaiting_payment', 'processing', 'shipped', 'completed', 'cancelled')", name: "orders_status_check"
    t.check_constraint "subtotal >= 0", name: "orders_subtotal_non_negative"
    t.check_constraint "total_amount >= 0", name: "orders_total_amount_non_negative"
  end

  create_table "password_reset_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_password_reset_tokens_on_user_id"
  end

  create_table "payment_proofs", force: :cascade do |t|
    t.bigint "payment_id", null: false
    t.string "storage_key", null: false
    t.string "original_filename", limit: 255, null: false
    t.string "mime_type", limit: 120
    t.integer "file_size", default: 0, null: false
    t.string "status", limit: 30, default: "submitted", null: false
    t.datetime "uploaded_at", null: false
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_id"], name: "index_payment_proofs_on_payment_id"
    t.index ["status"], name: "index_payment_proofs_on_status"
    t.check_constraint "file_size >= 0", name: "payment_proofs_file_size_non_negative"
    t.check_constraint "status IN ('submitted', 'approved', 'rejected')", name: "payment_proofs_status_check"
  end

  create_table "payment_verification_events", force: :cascade do |t|
    t.bigint "payment_id", null: false
    t.bigint "payment_proof_id"
    t.bigint "admin_id", null: false
    t.string "decision", limit: 20, null: false
    t.text "reason"
    t.datetime "created_at", null: false
    t.index ["admin_id"], name: "index_payment_verification_events_on_admin_id"
    t.index ["payment_id"], name: "index_payment_verification_events_on_payment_id"
    t.index ["payment_proof_id"], name: "index_payment_verification_events_on_payment_proof_id"
    t.check_constraint "decision IN ('approved', 'rejected')", name: "payment_verification_events_decision_check"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "payment_method", limit: 40, null: false
    t.integer "amount", null: false
    t.string "status", limit: 30, default: "pending", null: false
    t.bigint "verified_by"
    t.datetime "verified_at"
    t.text "rejection_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_payments_on_order_id", unique: true
    t.index ["status"], name: "index_payments_on_status"
    t.index ["verified_by"], name: "index_payments_on_verified_by"
    t.check_constraint "amount >= 0", name: "payments_amount_non_negative"
    t.check_constraint "status IN ('pending', 'waiting_verification', 'paid', 'rejected', 'expired', 'refunded')", name: "payments_status_check"
  end

  create_table "product_images", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "storage_key", null: false
    t.string "alt_text", limit: 180
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_product_images_on_product_id"
    t.check_constraint "position >= 0", name: "product_images_position_non_negative"
  end

  create_table "products", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.string "name", limit: 180, null: false
    t.string "slug", limit: 180, null: false
    t.string "sku", limit: 120, null: false
    t.text "description"
    t.integer "price", default: 0, null: false
    t.integer "stock_on_hand", default: 0, null: false
    t.integer "reserved_stock", default: 0, null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_products_on_category_id"
    t.index ["sku"], name: "index_products_on_sku", unique: true
    t.index ["slug"], name: "index_products_on_slug", unique: true
    t.check_constraint "price >= 0", name: "products_price_non_negative"
    t.check_constraint "reserved_stock <= stock_on_hand", name: "products_reserved_stock_within_stock"
    t.check_constraint "reserved_stock >= 0", name: "products_reserved_stock_non_negative"
    t.check_constraint "stock_on_hand >= 0", name: "products_stock_on_hand_non_negative"
  end

  create_table "refunds", force: :cascade do |t|
    t.bigint "payment_id", null: false
    t.bigint "order_id", null: false
    t.integer "amount", null: false
    t.text "reason", null: false
    t.string "status", limit: 20, default: "pending", null: false
    t.bigint "processed_by"
    t.datetime "processed_at"
    t.string "reference_number", limit: 80
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_refunds_on_order_id"
    t.index ["payment_id"], name: "index_refunds_on_payment_id"
    t.index ["processed_by"], name: "index_refunds_on_processed_by"
    t.index ["status"], name: "index_refunds_on_status"
    t.check_constraint "amount > 0", name: "refunds_amount_positive"
    t.check_constraint "status IN ('pending', 'processed', 'rejected')", name: "refunds_status_check"
  end

  create_table "reviews", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "product_id", null: false
    t.bigint "order_item_id", null: false
    t.integer "rating", null: false
    t.text "comment"
    t.boolean "is_visible", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_item_id"], name: "index_reviews_on_order_item_id", unique: true
    t.index ["product_id"], name: "index_reviews_on_product_id"
    t.index ["user_id"], name: "index_reviews_on_user_id"
    t.check_constraint "rating >= 1 AND rating <= 5", name: "reviews_rating_range"
  end

  create_table "shipments", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "shipping_method_id", null: false
    t.string "recipient_name_snapshot", limit: 150, null: false
    t.text "shipping_address_snapshot", null: false
    t.string "tracking_number", limit: 120
    t.string "status", limit: 30, default: "not_shipped", null: false
    t.datetime "shipped_at"
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_shipments_on_order_id", unique: true
    t.index ["shipping_method_id"], name: "index_shipments_on_shipping_method_id"
    t.index ["status"], name: "index_shipments_on_status"
    t.check_constraint "status IN ('not_shipped', 'packed', 'shipped', 'delivered')", name: "shipments_status_check"
  end

  create_table "shipping_methods", force: :cascade do |t|
    t.string "name", limit: 120, null: false
    t.text "description"
    t.integer "estimated_days", null: false
    t.integer "cost", default: 0, null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_shipping_methods_on_name", unique: true
    t.check_constraint "cost >= 0", name: "shipping_methods_cost_non_negative"
    t.check_constraint "estimated_days > 0", name: "shipping_methods_estimated_days_positive"
  end

  create_table "store_settings", force: :cascade do |t|
    t.string "setting_key", limit: 120, null: false
    t.text "setting_value", null: false
    t.bigint "updated_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["setting_key"], name: "index_store_settings_on_setting_key", unique: true
    t.index ["updated_by"], name: "index_store_settings_on_updated_by"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", limit: 150, null: false
    t.string "email", limit: 255, null: false
    t.string "password_digest", null: false
    t.string "role", limit: 20, default: "customer", null: false
    t.string "phone", limit: 30
    t.boolean "is_active", default: true, null: false
    t.datetime "email_verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.check_constraint "role IN ('admin', 'customer')", name: "users_role_check"
  end

  create_table "voucher_redemptions", force: :cascade do |t|
    t.bigint "voucher_id", null: false
    t.bigint "user_id", null: false
    t.bigint "order_id"
    t.string "status", limit: 20, default: "reserved", null: false
    t.datetime "reserved_at"
    t.datetime "used_at"
    t.datetime "released_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_voucher_redemptions_on_order_id", unique: true
    t.index ["status"], name: "index_voucher_redemptions_on_status"
    t.index ["user_id"], name: "index_voucher_redemptions_on_user_id"
    t.index ["voucher_id"], name: "index_voucher_redemptions_on_voucher_id"
    t.check_constraint "status IN ('reserved', 'used', 'released')", name: "voucher_redemptions_status_check"
  end

  create_table "vouchers", force: :cascade do |t|
    t.string "code", limit: 80, null: false
    t.text "description"
    t.string "discount_type", limit: 20, null: false
    t.integer "discount_value", default: 0, null: false
    t.integer "minimum_purchase", default: 0, null: false
    t.integer "maximum_discount", default: 0, null: false
    t.integer "usage_limit", default: 0, null: false
    t.integer "per_user_limit", default: 0, null: false
    t.datetime "starts_at"
    t.datetime "expires_at"
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_vouchers_on_code", unique: true
    t.index ["is_active"], name: "index_vouchers_on_is_active"
    t.check_constraint "discount_type IN ('fixed', 'percentage')", name: "vouchers_discount_type_check"
    t.check_constraint "discount_value >= 0", name: "vouchers_discount_value_non_negative"
    t.check_constraint "maximum_discount >= 0", name: "vouchers_maximum_discount_non_negative"
    t.check_constraint "minimum_purchase >= 0", name: "vouchers_minimum_purchase_non_negative"
    t.check_constraint "per_user_limit >= 0", name: "vouchers_per_user_limit_non_negative"
    t.check_constraint "usage_limit >= 0", name: "vouchers_usage_limit_non_negative"
  end

  create_table "wishlist_items", force: :cascade do |t|
    t.bigint "wishlist_id", null: false
    t.bigint "product_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_wishlist_items_on_product_id"
    t.index ["wishlist_id", "product_id"], name: "index_wishlist_items_on_wishlist_id_and_product_id", unique: true
    t.index ["wishlist_id"], name: "index_wishlist_items_on_wishlist_id"
  end

  create_table "wishlists", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_wishlists_on_user_id", unique: true
  end

  add_foreign_key "addresses", "users", on_delete: :restrict
  add_foreign_key "audit_logs", "users", on_delete: :restrict
  add_foreign_key "cancellation_requests", "orders", on_delete: :restrict
  add_foreign_key "cancellation_requests", "users", column: "requested_by", on_delete: :restrict
  add_foreign_key "cancellation_requests", "users", column: "reviewed_by", on_delete: :restrict
  add_foreign_key "cart_items", "carts", on_delete: :restrict
  add_foreign_key "cart_items", "products", on_delete: :restrict
  add_foreign_key "carts", "users", on_delete: :restrict
  add_foreign_key "idempotency_keys", "users", on_delete: :restrict
  add_foreign_key "inventory_movements", "orders", on_delete: :restrict
  add_foreign_key "inventory_movements", "products", on_delete: :restrict
  add_foreign_key "inventory_movements", "users", column: "created_by", on_delete: :restrict
  add_foreign_key "inventory_reservations", "orders", on_delete: :restrict
  add_foreign_key "inventory_reservations", "products", on_delete: :restrict
  add_foreign_key "notifications", "users", on_delete: :restrict
  add_foreign_key "order_items", "orders", on_delete: :restrict
  add_foreign_key "order_items", "products", on_delete: :restrict
  add_foreign_key "orders", "shipping_methods", on_delete: :restrict
  add_foreign_key "orders", "users", on_delete: :restrict
  add_foreign_key "password_reset_tokens", "users", on_delete: :restrict
  add_foreign_key "payment_proofs", "payments", on_delete: :restrict
  add_foreign_key "payment_verification_events", "payment_proofs", on_delete: :restrict
  add_foreign_key "payment_verification_events", "payments", on_delete: :restrict
  add_foreign_key "payment_verification_events", "users", column: "admin_id", on_delete: :restrict
  add_foreign_key "payments", "orders", on_delete: :restrict
  add_foreign_key "payments", "users", column: "verified_by", on_delete: :restrict
  add_foreign_key "product_images", "products", on_delete: :restrict
  add_foreign_key "products", "categories", on_delete: :restrict
  add_foreign_key "refunds", "orders", on_delete: :restrict
  add_foreign_key "refunds", "payments", on_delete: :restrict
  add_foreign_key "refunds", "users", column: "processed_by", on_delete: :restrict
  add_foreign_key "reviews", "order_items", on_delete: :restrict
  add_foreign_key "reviews", "products", on_delete: :restrict
  add_foreign_key "reviews", "users", on_delete: :restrict
  add_foreign_key "shipments", "orders", on_delete: :restrict
  add_foreign_key "shipments", "shipping_methods", on_delete: :restrict
  add_foreign_key "store_settings", "users", column: "updated_by", on_delete: :restrict
  add_foreign_key "voucher_redemptions", "orders", on_delete: :restrict
  add_foreign_key "voucher_redemptions", "users", on_delete: :restrict
  add_foreign_key "voucher_redemptions", "vouchers", on_delete: :restrict
  add_foreign_key "wishlist_items", "products", on_delete: :restrict
  add_foreign_key "wishlist_items", "wishlists", on_delete: :restrict
  add_foreign_key "wishlists", "users", on_delete: :restrict
end
