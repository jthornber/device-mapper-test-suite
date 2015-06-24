require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'

#----------------------------------------------------------------

module MetadataUtils
  def assert_identical_files(f1, f2)
    begin
      ProcessControl::run("diff -bu #{f1} #{f2}")
    rescue
      flunk("files differ #{f1} #{f2}")
    end
  end

  # Reads the metadata from an _inactive_ pool
  def dump_metadata(dev, held_root = nil)
    metadata = nil
    held_root_arg = held_root ? "-m #{held_root}" : ''
    Utils::with_temp_file('metadata_xml') do |file|
      ProcessControl::run("thin_dump #{held_root_arg} #{dev} > #{file.path}")
      file.rewind
      yield(file.path)
    end
  end

  def restore_metadata(xml_path, dev)
    ProcessControl::run("thin_restore -i #{xml_path} -o #{dev}")
  end

  def read_held_root(pool, dev)
    metadata = nil

    status = PoolStatus.new(pool)
    Utils::with_temp_file('metadata_xml') do |file|
      ProcessControl::run("thin_dump -m#{status.held_root} #{dev} > #{file.path}")
      file.rewind
      metadata = read_xml(file)
    end

    metadata
  end

  def read_metadata(dev)
    metadata = nil

    Utils::with_temp_file('metadata_xml') do |file|
      ProcessControl::run("thin_dump #{dev} > #{file.path}")
      file.rewind
      metadata = read_xml(file)
    end

    metadata
  end
end

#----------------------------------------------------------------
