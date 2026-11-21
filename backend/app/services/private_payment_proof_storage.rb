require "securerandom"

class PrivatePaymentProofStorage
  ROOT = Rails.root.join("storage", "private", "payment_proofs")
  MAX_SIZE = 5.megabytes

  def self.store(upload, root: ROOT)
    key = "#{SecureRandom.hex(32)}#{File.extname(upload.original_filename).downcase}"
    path = root.join(key)
    FileUtils.mkdir_p(root)
    upload.tempfile.rewind
    File.binwrite(path, upload.tempfile.read)
    [ key, path ]
  end

  def self.open(key, root: ROOT)
    candidate = root.join(key).expand_path
    raise ArgumentError, "invalid storage key" unless candidate.dirname == root.expand_path && candidate.basename.to_s == key

    VerifiedStorageFile.open(candidate, root: root, max_size: MAX_SIZE)
  end
end
