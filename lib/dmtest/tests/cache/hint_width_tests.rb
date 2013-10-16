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

class HintWidthTests < ThinpTestCase
  include Tags
  include Utils
  include DiskUnits
  extend TestUtils
  include CacheXML
  include ThinpXML

  def setup
    super
    @data_block_size = k(64)
  end

  def dump_metadata(dev)
    output = ProcessControl.run("cache_dump #{dev}")
    read_xml(StringIO.new(output))
  end

  #--------------------------------

  def test_various_hint_widths_can_be_reloaded
    [4, 32, 96, 128].each do |hint_size|

      stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                             :format => true, :data_size => gig(1), :policy => Policy.new('hints', :hint_size => hint_size))
      stack.activate do |stack|
        # repeatedly wipe the same chunk of the cache to trigger promotion
        5.times do
          wipe_device(stack.cache, 10240)
        end

        status = CacheStatus.new(stack.cache)
        assert(status.residency > 0)
      end

      stack.opts[:format] = false
      stack.activate do |stack|
      end
    end
  end

  def test_hint_size_is_dumped_correctly
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :format => true, :data_size => gig(1), :policy => Policy.new('hints', :hint_size => 96))
    stack.activate_support_devs do |stack|
      stack.activate_top_level {|stack|}

      md = dump_metadata(stack.md)
      assert_equal(96, md.superblock.hint_width)
    end
  end
end

#----------------------------------------------------------------
