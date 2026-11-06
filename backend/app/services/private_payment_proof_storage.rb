require "securerandom"

class PrivatePaymentProofStorage
  ROOT = Rails.root.join("storage", "private", "payment_proofs")

  def self.store(upload)
    key = "#{SecureRandom.hex(32)}#{File.extname(upload.original_filename).downcase}"
    path = ROOT.join(key)
    FileUtils.mkdir_p(ROOT)
    upload.tempfile.rewind
    File.binwrite(path, upload.tempfile.read)
    [key, path]
  end

  def self.path(key)
    candidate = ROOT.join(key).expand_path
    raise ArgumentError, "invalid storage key" unless candidate.dirname == ROOT.expand_path && candidate.basename.to_s == key

    candidate
  end
end
