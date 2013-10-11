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

class CorrectnessTests < ThinpTestCase
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
      sleep 1                   # FIXME: needed to avoid udev fiddling
    end
  end

  def test_can_dump_kernel_metadata
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :format => true, :data_size => gig(1))

    stack.activate_support_devs do |stack|
      stack.activate_top_level do |stack|
        sleep 1
      end

      ProcessControl.run("cache_dump -o dump.xml #{stack.md}")
    end
  end
end

#----------------------------------------------------------------
