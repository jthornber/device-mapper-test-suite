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

#----------------------------------------------------------------

class PassthroughTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  extend TestUtils

  def setup
    super
    @data_block_size = meg(1)
  end

  def prepare_populated_cache()
    xml_file = 'metadata.xml'
    cache_blocks = 1024
    ProcessControl.run("cache_xml create --nr-cache-blocks #{cache_blocks} --nr-mappings #{cache_blocks} > #{xml_file}")

    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :cache_size => cache_blocks * 64,
                           :block_size => 64,
                           :format => true, :data_size => meg(128),
                           :policy => Policy.new('mq'))
    stack.activate_support_devs do |stack|
      ProcessControl.run("cache_restore -i #{xml_file} -o #{stack.md}")
      ProcessControl.run("cache_dump #{stack.md} > metadata2.xml")
      stack.activate_top_level do |stack|
        status = CacheStatus.new(stack.cache)
        assert_equal(cache_blocks, status.residency)
      end

      ProcessControl.run("cache_dump #{stack.md} > metadata3.xml")
    end
  end

  #--------------------------------

  def test_passthrough_never_promotes
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :format => true, :data_size => gig(1),
                           :policy => Policy.new('mq'),
                           :io_mode => :passthrough)
    stack.activate do |stack|
      100.times {wipe_device(stack.cache, 640)}

      status = CacheStatus.new(stack.cache)
      assert_equal(0, status.promotions)
      assert_equal(0, status.residency)
    end
  end

  def test_passthrough_demotes_writes
    prepare_populated_cache()

    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :block_size => 64,
                           :cache_size => 1024 * 64,
                           :format => false, :data_size => meg(128),
                           :policy => Policy.new('mq'),
                           :io_mode => :passthrough)
    stack.activate_support_devs do |stack|
      stack.activate_top_level do |stack|
        wipe_device(stack.cache)

        status = CacheStatus.new(stack.cache)
        assert_equal(0, status.residency)
      end
    end
  end

  def test_passthrough_does_not_demote_reads
    prepare_populated_cache()

    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :block_size => 64,
                           :cache_size => 1024 * 64,
                           :format => false,
                           :data_size => meg(128),
                           :policy => Policy.new('mq'),
                           :io_mode => :passthrough)

    stack.activate_support_devs do |stack|
      stack.activate_top_level do |stack|
        read_device_to_null(stack.cache)

        status = CacheStatus.new(stack.cache)
        assert_equal(1024, status.residency)
      end
    end
  end
end

#----------------------------------------------------------------
