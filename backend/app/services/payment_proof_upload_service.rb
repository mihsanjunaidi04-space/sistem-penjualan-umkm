class PaymentProofUploadService
  MAX_SIZE = 5.megabytes
  ALLOWED = {
    ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".png" => "image/png", ".webp" => "image/webp"
  }.freeze

  class Error < StandardError
    attr_reader :code
    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  def self.call(payment:, upload:)
    raise Error.new("FILE_REQUIRED", "Bukti transfer wajib diunggah.") if upload.blank?
    raise Error.new("FILE_TOO_LARGE", "Ukuran bukti transfer maksimal 5 MB.") if upload.size > MAX_SIZE

    extension = File.extname(upload.original_filename.to_s).downcase
    detected = Marcel::MimeType.for(upload.tempfile, name: upload.original_filename.to_s)
    raise Error.new("INVALID_FILE_TYPE", "Bukti transfer harus berupa JPG, PNG, atau WEBP yang valid.") unless ALLOWED[extension] == detected

    key, = PrivatePaymentProofStorage.store(upload)
    PaymentProof.create!(payment: payment, storage_key: key, original_filename: upload.original_filename.to_s.truncate(255), mime_type: detected, file_size: upload.size, status: "submitted", uploaded_at: Time.current)
  rescue IOError
    raise Error.new("INVALID_FILE_TYPE", "Isi file bukti transfer tidak valid.")
  end
end
