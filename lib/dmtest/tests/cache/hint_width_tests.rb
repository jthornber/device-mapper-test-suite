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

require 'rspec'

#----------------------------------------------------------------

class HintWidthTests < ThinpTestCase
  include Tags
  include Utils
  include DiskUnits
  extend TestUtils

  def setup
    super
    @data_block_size = k(64)
  end

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
end

#----------------------------------------------------------------
