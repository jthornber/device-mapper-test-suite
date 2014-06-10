require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/thinp-test'
require 'dmtest/xml_format'

#----------------------------------------------------------------

module MetadataGenerator
  include XMLFormat

  def data_dev_blocks
    dev_size(@data_dev) / @data_block_size
  end

  def create_linear_metadata(dev_count, dev_size)
    superblock = Superblock.new("uuid here", 0, 1, 128, data_dev_blocks)

    devices = Array.new
    offset = 0
    0.upto(dev_count - 1) do |dev|
      nr_mappings = dev_size
      mappings = Array.new
      1.upto(nr_mappings) {|n| mappings << Mapping.new(n, offset + n, 1, 1)}
      devices << Device.new(dev, nr_mappings, 0, 0, 0, mappings)

      offset += nr_mappings
    end

    Metadata.new(superblock, devices)
  end

  def create_metadata(dev_count, dev_size, block_mapper)
    nr_data_blocks = dev_size * dev_count
    superblock = Superblock.new("uuid here", 0, 1, 128, data_dev_blocks)

    devices = Array.new
    offset = 0
    dest_blocks = self.send(block_mapper, nr_data_blocks)

    0.upto(dev_count - 1) do |dev|
      nr_mappings = dev_size
      mappings = Array.new
      0.upto(nr_mappings - 1) do |n|
        mappings << Mapping.new(n, dest_blocks[offset + n], 1, 1)
      end
      devices << Device.new(dev, nr_mappings, 0, 0, 0, mappings)

      offset += nr_mappings
    end

    Metadata.new(superblock, devices)
  end

  # allocators
  def linear_array(len)
    ary = Array.new
    (0..(len - 1)).each {|n| ary[n] = n}
    ary
  end

  def shuffled_array(len)
    ary = linear_array(len)

    (0..(len - 1)).each do |n|
      n2 = n + rand(len - n)
      tmp = ary[n]
      ary[n] = ary[n2]
      ary[n2] = tmp
    end

    ary
  end
end

#----------------------------------------------------------------
