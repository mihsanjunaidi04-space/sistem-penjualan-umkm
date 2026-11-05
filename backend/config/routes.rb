Rails.application.routes.draw do
  get '/health', to: 'health_check#index'

  scope :auth, module: :auth do
    post '/register', action: :register
    post '/login', action: :login
    delete '/logout', action: :logout
    get '/me', action: :me
    get '/admin', action: :admin_only
    get '/customer', action: :customer_only
  end

  get 'up' => 'rails/health#show', as: :rails_health_check

  match '*unmatched', to: 'errors#not_found', via: :all
end
