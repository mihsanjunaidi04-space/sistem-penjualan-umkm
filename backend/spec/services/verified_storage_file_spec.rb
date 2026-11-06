require 'rails_helper'
require 'tmpdir'

RSpec.describe VerifiedStorageFile do
  around do |example|
    Dir.mktmpdir('verified-storage') do |directory|
      @root = Pathname.new(directory).join('storage')
      @root.mkpath
      example.run
    end
  end

  def write_file(relative_path, content = 'safe')
    path = @root.join(relative_path)
    path.dirname.mkpath
    File.binwrite(path, content)
    path
  end

  def create_symlink(target, link)
    File.symlink(target, link)
  rescue NotImplementedError, Errno::EACCES, Errno::EPERM
    skip "symlink creation is unavailable on this filesystem; symlink rejection is covered on supported filesystems"
  end

  it 'streams a regular file from the root' do
    path = write_file('product_images/normal.png', 'image')
    file = described_class.open(path, root: @root, max_size: 100)

    expect(file.each.to_a.join).to eq('image')
    expect(file.size).to eq(5)
  end

  it 'rejects lexical traversal and root-prefix collisions' do
    outside = Pathname.new(@root.dirname).join('outside.txt')
    File.write(outside, 'outside')
    evil_root = Pathname.new("#{@root}_evil")
    evil_root.mkpath
    evil = write_file('evil.txt')

    expect { described_class.open(@root.join('../outside.txt'), root: @root, max_size: 100) }.to raise_error(ArgumentError)
    expect { described_class.open(evil, root: evil_root, max_size: 100) }.to raise_error(ArgumentError)
  end

  it 'rejects a symlink to a file outside the root' do
    outside = Pathname.new(@root.dirname).join('outside.txt')
    File.write(outside, 'outside')
    link = @root.join('outside-link')
    create_symlink(outside, link)

    expect { described_class.open(link, root: @root, max_size: 100) }.to raise_error(ArgumentError)
  end

  it 'rejects a symlink to a file inside the root' do
    target = write_file('target.txt')
    link = @root.join('inside-link')
    create_symlink(target, link)

    expect { described_class.open(link, root: @root, max_size: 100) }.to raise_error(ArgumentError)
  end

  it 'rejects missing files, directories, and files above the size limit' do
    directory = @root.join('directory')
    directory.mkpath
    large = write_file('large.txt', '123456')

    expect { described_class.open(@root.join('missing.txt'), root: @root, max_size: 100) }.to raise_error(ArgumentError)
    expect { described_class.open(directory, root: @root, max_size: 100) }.to raise_error(ArgumentError)
    expect { described_class.open(large, root: @root, max_size: 5) }.to raise_error(ArgumentError)
  end

  it 'uses descriptor verification when File::NOFOLLOW is unavailable' do
    path = write_file('no-follow-check.txt')
    file = described_class.open(path, root: @root, max_size: 100)

    if File.const_defined?(:NOFOLLOW)
      expect(File::NOFOLLOW).to be_a(Integer)
    else
      expect(file.each.to_a.join).to eq('safe')
    end
  end
end
