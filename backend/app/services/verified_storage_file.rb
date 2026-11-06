class VerifiedStorageFile
  CHUNK_SIZE = 16 * 1024

  attr_reader :size

  def path
    @file.path
  end

  def self.open(path, root:, max_size:)
    candidate = Pathname.new(path.respond_to?(:to_path) ? path.to_path : path.to_s).expand_path
    root = Pathname.new(root.respond_to?(:to_path) ? root.to_path : root.to_s).expand_path
    raise ArgumentError, "invalid storage path" unless within?(candidate, root)

    file = File.open(candidate.to_s, open_flags)
    begin
      verify!(file, candidate, root, max_size)
      new(file)
    rescue StandardError
      file.close unless file.closed?
      raise ArgumentError, "invalid storage file"
    end
  rescue SystemCallError, TypeError
    raise ArgumentError, "invalid storage file"
  end

  def self.open_flags
    flags = File::RDONLY | File::BINARY
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end
  private_class_method :open_flags

  def self.verify!(file, candidate, root, max_size)
    stat = file.stat
    raise ArgumentError unless stat.file? && stat.size <= max_size

    real_path = Pathname.new(File.realpath(candidate.to_s)).expand_path
    real_root = Pathname.new(File.realpath(root.to_s)).expand_path
    raise ArgumentError unless within?(real_path, real_root)
    raise ArgumentError if symlink_component?(candidate, root)
    raise ArgumentError unless File.identical?(file, real_path.to_s)
  end
  private_class_method :verify!

  def self.within?(path, root)
    path_string = path.to_s
    root_string = "#{root}#{File::SEPARATOR}"
    if Gem.win_platform?
      path_string.downcase.start_with?(root_string.downcase)
    else
      path_string.start_with?(root_string)
    end
  end
  private_class_method :within?

  def self.symlink_component?(path, root)
    current = root
    path.relative_path_from(root).each_filename do |component|
      current = current.join(component)
      return true if File.lstat(current.to_s).symlink?
    end
    false
  end
  private_class_method :symlink_component?

  def initialize(file)
    @file = file
    @size = file.stat.size
  end

  def each
    return enum_for(:each) unless block_given?

    begin
      while (chunk = @file.read(CHUNK_SIZE))
        yield chunk
      end
    ensure
      close
    end
  end

  def close
    @file.close unless @file.closed?
  end
end
