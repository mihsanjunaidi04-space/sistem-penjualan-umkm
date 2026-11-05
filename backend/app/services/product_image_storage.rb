require 'securerandom'
require 'fileutils'

class ProductImageStorage
  MAX_SIZE = 5.megabytes
  ALLOWED_TYPES = {
    'image/jpeg' => '.jpg',
    'image/png' => '.png',
    'image/webp' => '.webp'
  }.freeze

  def self.store(upload)
    raise ArgumentError, 'File gambar wajib diisi.' unless upload.respond_to?(:content_type) && upload.respond_to?(:tempfile)
    extension = ALLOWED_TYPES[upload.content_type.to_s.downcase]
    raise ArgumentError, 'Format gambar harus JPEG, PNG, atau WebP.' unless extension
    original_extension = File.extname(upload.original_filename.to_s).downcase
    raise ArgumentError, 'Ekstensi gambar tidak sesuai dengan MIME type.' unless original_extension == extension
    raise ArgumentError, 'Ukuran gambar maksimal 5 MB.' if upload.tempfile.size > MAX_SIZE

    key = "product_images/#{SecureRandom.uuid}#{extension}"
    path = Rails.root.join('storage', key)
    FileUtils.mkdir_p(path.dirname)
    upload.tempfile.rewind
    File.binwrite(path, upload.tempfile.read)
    key
  end

  def self.delete(storage_key)
    return if storage_key.blank?

    path = Rails.root.join('storage', storage_key)
    File.delete(path) if path.file? && path.to_s.start_with?(Rails.root.join('storage').to_s)
  end

  def self.path(storage_key)
    path = Rails.root.join('storage', storage_key)
    return nil unless path.to_s.start_with?(Rails.root.join('storage').to_s) && path.file?

    path
  end
end
