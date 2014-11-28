require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_policy'

#----------------------------------------------------------------

class ToolsTests < ThinpTestCase
  include Tags
  include Utils
  include DiskUnits
  extend TestUtils

  def setup
    super
    @data_block_size = meg(1)
  end

  def with_standard_cache(opts = Hash.new, &block)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      block.call(stack.cache)
    end
  end

  def test_formatting_in_kernel_works
    with_standard_cache(:format => true, :data_size => gig(1)) do |cache|
    end
  end

  def test_can_dump_kernel_metadata
    ProcessControl.run("which cache_check")

    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :format => true, :data_size => gig(1))

    stack.activate_support_devs do |stack|
      stack.activate_top_level do |stack|
      end

      ProcessControl.run("cache_dump -o dump.xml #{stack.md}")
    end
  end

  def test_can_restore_from_xml
    # generate some xml metadata
    xml_file = 'metadata.xml'
    ProcessControl.run("cache_xml create --nr-cache-blocks uniform[100..500] --nr-mappings uniform[50..100] > #{xml_file}")

    #bring up the metadata device
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :format => true,
                           :data_size => gig(1),
                           :block_size => k(64))
    stack.activate_support_devs do |stack|
      # restore from xml
      ProcessControl.run("cache_restore -i #{xml_file} -o #{stack.md}")

      # Bring up the kernel cache target to validate the metadata
      stack.activate_top_level do |stack|
        # wipe the cached device, to exercise the metadata
        wipe_device(stack.cache)
      end
    end
  end
end

#----------------------------------------------------------------
