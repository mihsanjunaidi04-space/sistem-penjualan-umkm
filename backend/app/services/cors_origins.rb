require "uri"

class CorsOrigins
  DNS_LABEL_PATTERN = /\A[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\z/

  def self.production(value)
    origins = value.to_s.split(",", -1).map(&:strip)
    if origins.empty? || origins.any?(&:empty?)
      raise ArgumentError, "CORS_ALLOWED_ORIGINS must contain non-empty origins"
    end

    origins.each { |origin| validate_origin!(origin) }
    origins.uniq
  end

  def self.validate_origin!(origin)
    uri = URI.parse(origin)
    unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? &&
        uri.path.empty? && uri.query.nil? && uri.fragment.nil?
      raise ArgumentError, "CORS_ALLOWED_ORIGINS entries must be HTTPS origins without userinfo, path, query, or fragment"
    end

    hostname = uri.host
    labels = hostname.split(".", -1)
    valid_hostname = hostname.bytesize <= 253 && labels.all? do |label|
      label.bytesize.between?(1, 63) && DNS_LABEL_PATTERN.match?(label)
    end
    unless valid_hostname
      raise ArgumentError, "CORS_ALLOWED_ORIGINS entries must contain a valid DNS hostname"
    end

    unless uri.port.between?(1, 65_535)
      raise ArgumentError, "CORS_ALLOWED_ORIGINS ports must be between 1 and 65535"
    end
  rescue URI::InvalidURIError => error
    raise ArgumentError, "CORS_ALLOWED_ORIGINS contains an invalid origin: #{error.message}"
  end
  private_class_method :validate_origin!
end
