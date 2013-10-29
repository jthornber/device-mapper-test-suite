require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/tests/cache/cache_stack'
require 'dmtest/tests/cache/policy'
require 'thinp_xml/cache_xml'

#----------------------------------------------------------------

class ResizeTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  extend TestUtils
  include CacheXML
  include ThinpXML

  def setup
    super
    @data_block_size = k(32)
    @cache_blocks = 1024
  end

  def make_stack(overrides = Hash.new)
    cache_size = overrides.fetch(:cache_blocks, @cache_blocks) * @data_block_size

    opts = {
      :cache_size => cache_size,
      :block_size => @data_block_size,
      :format => true,
      :data_size => meg(128),
      :policy => Policy.new('mq')
    }

    CacheStack.new(@dm, @metadata_dev, @data_dev, opts.merge(overrides))
  end

  def prepare_populated_cache(overrides = Hash.new)
    nr_blocks = overrides.fetch(:cache_blocks, @cache_blocks)

    xml_file = 'metadata.xml'
    ProcessControl.run("cache_xml create --nr-cache-blocks #{nr_blocks} --nr-mappings #{nr_blocks} > #{xml_file}")

    s = make_stack(overrides)
    s.activate_support_devs do
      ProcessControl.run("cache_restore -i #{xml_file} -o #{s.md}")

      s.activate_top_level do
        status = CacheStatus.new(s.cache)
        assert_equal(nr_blocks, status.residency)
      end

      ProcessControl.run("cache_dump #{s.md} > metadata1.xml")
    end
  end

  def dump_metadata(dev)
    output = ProcessControl.run("cache_dump #{dev}")
    read_xml(StringIO.new(output))
  end

  #--------------------------------

  def test_no_resize_retains_mappings
#    [23, 513, 1023, 4095].each do |nr_blocks|
    [4095].each do |nr_blocks|
      prepare_populated_cache(:cache_blocks => nr_blocks)

    #   s = make_stack(:format => false,
    #                  :cache_blocks => nr_blocks)
    #   s.activate_support_devs do
    #     md1 = dump_metadata(s.md)

    #     s.activate_top_level do
    #     end

    #     md2 = dump_metadata(s.md)
    #     assert_equal(md1.mappings, md2.mappings)
    #   end
    end
  end
end

#----------------------------------------------------------------
