require "securerandom"
require "fileutils"

class ProductImageStorage
  MAX_SIZE = 5.megabytes
  ALLOWED_TYPES = {
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/webp" => ".webp"
  }.freeze

  def self.store(upload)
    raise ArgumentError, "File gambar wajib diisi." unless upload.respond_to?(:content_type) && upload.respond_to?(:tempfile)
    extension = ALLOWED_TYPES[upload.content_type.to_s.downcase]
    raise ArgumentError, "Format gambar harus JPEG, PNG, atau WebP." unless extension
    original_extension = File.extname(upload.original_filename.to_s).downcase
    raise ArgumentError, "Ekstensi gambar tidak sesuai dengan MIME type." unless original_extension == extension
    raise ArgumentError, "Ukuran gambar maksimal 5 MB." if upload.tempfile.size > MAX_SIZE

    key = "product_images/#{SecureRandom.uuid}#{extension}"
    path = Rails.root.join("storage", key)
    FileUtils.mkdir_p(path.dirname)
    upload.tempfile.rewind
    File.binwrite(path, upload.tempfile.read)
    key
  end

  def self.delete(storage_key)
    return if storage_key.blank?

    path = path_for(storage_key)
    File.delete(path) if path&.file?
  end

  def self.open(storage_key)
    VerifiedStorageFile.open(Rails.root.join("storage", storage_key.to_s), root: Rails.root.join("storage"), max_size: MAX_SIZE)
  end

  def self.path_for(storage_key)
    root = Rails.root.join("storage").expand_path
    path = root.join(storage_key.to_s).expand_path
    return nil unless path.to_s.start_with?("#{root}#{File::SEPARATOR}")

    path
  end
end
