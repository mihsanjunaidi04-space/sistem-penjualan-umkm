require "pathname"

class OrphanPaymentProofDetectionService
  BATCH_SIZE = 100
  STORAGE_KEY_REGEX = /\A\h{64}\.(?:jpe?g|png|webp)\z/i
  MIN_AGE = 1.day
  SPECIAL_ENTRIES = %w[. ..].freeze

  def self.call(min_age: MIN_AGE, batch_size: BATCH_SIZE, cursor: nil, root: PrivatePaymentProofStorage::ROOT)
    new(min_age: min_age, batch_size: batch_size, cursor: cursor, root: root).call
  end

  def initialize(min_age: MIN_AGE, batch_size: BATCH_SIZE, cursor: nil, root: PrivatePaymentProofStorage::ROOT)
    @min_age = min_age
    @batch_size = batch_size
    @cursor = cursor
    @root = root.is_a?(Pathname) ? root : Pathname.new(root.to_s)
  end

  def call
    return empty_result unless @root.directory?

    entries = enumerate_entries
    return failed_result if entries.nil?

    entries = entries.sort_by { |entry| entry.basename.to_s }
    entries = entries.select { |entry| entry.basename.to_s > @cursor } if @cursor.present?

    batch = entries.first(@batch_size)
    remaining = entries.drop(@batch_size)

    stats = empty_stats
    last_success = nil

    batch.each do |entry|
      stats[:scanned] += 1

      category = classify(entry)
      if category == :failed
        stats[:failed] += 1
        break
      end

      stats[category] += 1
      stats[:processed] += 1
      last_success = entry.basename.to_s
    end

    next_cursor = if stats[:failed].positive?
                    last_success || @cursor
    else
                    batch.last&.basename&.to_s
    end
    has_more = remaining.any? || stats[:failed].positive?

    result(stats, next_cursor, has_more)
  end

  private

  def enumerate_entries
    @root.entries
         .reject { |entry| SPECIAL_ENTRIES.include?(entry.basename.to_s) }
         .map { |entry| @root.join(entry.basename) }
  rescue SystemCallError
    nil
  end

  def classify(entry)
    lstat = entry.lstat

    return :symlink if lstat.symlink?
    return :invalid_type unless lstat.file?

    name = entry.basename.to_s
    return :invalid_name unless name.match?(STORAGE_KEY_REGEX)

    begin
      mtime = entry.mtime
    rescue SystemCallError
      return :failed
    end
    return :too_recent if mtime > Time.current - @min_age

    begin
      PaymentProof.where(storage_key: name).exists? ? :referenced : :orphaned
    rescue ActiveRecord::StatementInvalid,
           ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionFailed,
           ActiveRecord::DatabaseConnectionError,
           SQLite3::BusyException
      :failed
    end
  rescue SystemCallError
    :failed
  end

  def empty_stats
    {
      scanned: 0, processed: 0, failed: 0,
      orphaned: 0, referenced: 0, too_recent: 0,
      invalid_name: 0, symlink: 0, invalid_type: 0
    }
  end

  def empty_result
    result(empty_stats, nil, false)
  end

  def failed_result
    stats = empty_stats
    stats[:failed] = 1
    result(stats, @cursor, true)
  end

  def result(stats, next_cursor, has_more)
    {
      scanned: stats[:scanned],
      processed: stats[:processed],
      failed: stats[:failed],
      orphaned: stats[:orphaned],
      referenced: stats[:referenced],
      too_recent: stats[:too_recent],
      invalid_name: stats[:invalid_name],
      symlink: stats[:symlink],
      invalid_type: stats[:invalid_type],
      next_cursor: next_cursor,
      has_more: has_more
    }
  end
end
