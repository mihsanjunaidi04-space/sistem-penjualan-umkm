# Be sure to restart your server when you modify this file.

require Rails.root.join("app/services/cors_origins")
require Rails.root.join("app/services/jwt_service")

origins = if Rails.env.production?
  CorsOrigins.production(ENV["CORS_ALLOWED_ORIGINS"])
else
  [ "http://localhost:5173" ]
end

# Validate production JWT configuration during application boot.
JwtService.secret_key if Rails.env.production?

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*origins)

    resource "*",
      headers: :any,
      methods: [ :get, :post, :patch, :delete, :options ],
      credentials: false
  end
end
