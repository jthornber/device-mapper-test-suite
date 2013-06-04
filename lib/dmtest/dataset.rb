require 'dmtest/dataset'
require 'dmtest/fs'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'

# these added for the dataset stuff
require 'fileutils'

#----------------------------------------------------------------

class DatasetFile < Struct.new(:path, :size)
end

class Dataset
  attr_accessor :files

  def initialize(files)
    @files = files
  end

  def apply(count = nil)
    if count.nil? || count >= @files.size
      files.each do |f|
        create_file(f.path, f.size)
      end
    else
      0.upto(count) do |i|
        f = @files[i]
        create_file(f.path, f.size)
      end
    end
  end

  def Dataset.read(path)
    files = Array.new

    File.open(path) do |file|
      while line = file.gets
        m = line.match(/(\S+)\s(\d+)/)
        unless m.nil?
          files << DatasetFile.new(m[1], m[2].to_i)
        end
      end
    end

    Dataset.new(files)
  end

  private
  def breakup_path(path)
    elements = path.split('/')
    return [elements[0..elements.size - 2].join('/'), elements[elements.size - 1]]
  end

  def in_directory(dir)
    FileUtils.makedirs(dir)
    Dir.chdir(dir) do
      yield
    end
  end

  def create_file(path, size)
    dir, name = breakup_path(path)

    in_directory(dir) do
      File.open(name, "wb") do |file|
        file.syswrite('-' * size)
      end
    end
  end
end

#----------------------------------------------------------------
