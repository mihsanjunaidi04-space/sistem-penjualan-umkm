Rails.application.routes.draw do
  get "/health", to: "health_check#index"

  scope :auth, module: :auth do
    post "/register", action: :register
    post "/login", action: :login
    delete "/logout", action: :logout
    get "/me", action: :me
    get "/admin", action: :admin_only
    get "/customer", action: :customer_only
  end

  get "/categories", to: "categories#index"
  get "/categories/:slug", to: "categories#show"
  get "/products", to: "products#index"
  get "/products/:slug", to: "products#show"
  get "/products/:slug/images/:image_id", to: "products#image"
  get "/shipping-methods", to: "shipping_methods#index"

  get "/cart", to: "cart#index"
  post "/cart/items", to: "cart#create_item"
  patch "/cart/items/:id", to: "cart#update_item"
  delete "/cart/items/:id", to: "cart#destroy_item"
  delete "/cart/items", to: "cart#clear"
  get "/customer/addresses", to: "addresses#index"
  post "/checkout", to: "checkout#create"
  get "/customer/orders", to: "orders#index"
  get "/customer/orders/:id", to: "orders#show"
  get "/customer/orders/:order_id/cancellation-requests", to: "cancellation_requests#index"
  post "/customer/orders/:order_id/cancellation-requests", to: "cancellation_requests#create"
  post "/customer/orders/:order_id/payment-proof", to: "payments#upload_proof"
  get "/customer/orders/:order_id/payment-proofs/:proof_id", to: "payments#proof"

  namespace :admin do
    get "/orders", to: "orders#index"
    get "/orders/:id", to: "orders#show"
    post "/orders/:order_id/shipments", to: "shipments#create"
    patch "/shipments/:id/pack", to: "shipments#pack"
    patch "/shipments/:id/ship", to: "shipments#ship"
    patch "/shipments/:id/deliver", to: "shipments#deliver"
    get "/cancellation-requests", to: "cancellation_requests#index"
    post "/cancellation-requests/:id/approve", to: "cancellation_requests#approve"
    post "/cancellation-requests/:id/reject", to: "cancellation_requests#reject"
    get "/payments", to: "payments#index"
    get "/payments/:id", to: "payments#show"
    get "/payments/:id/proofs/:proof_id", to: "payments#proof"
    post "/payments/:id/approve", to: "payments#approve"
    post "/payments/:id/reject", to: "payments#reject"
    get "/payment-settings", to: "payments#settings"
    patch "/payment-settings", to: "payments#update_settings"
    get "/categories", to: "categories#index"
    post "/categories", to: "categories#create"
    patch "/categories/:id", to: "categories#update"
    get "/products", to: "products#index"
    post "/products", to: "products#create"
    patch "/products/:id", to: "products#update"
    post "/products/:id/images", to: "products#upload_image"
    delete "/products/:id/images/:image_id", to: "products#delete_image"
  end

  get "up" => "rails/health#show", as: :rails_health_check

  match "*unmatched", to: "errors#not_found", via: :all
end
