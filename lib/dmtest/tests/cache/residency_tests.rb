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

class ResidencyTests < ThinpTestCase
  include Tags
  include Utils
  include DiskUnits
  extend TestUtils

  def setup
    super
    @data_block_size = meg(1)
  end

  def standard_stack
    CacheStack.new(@dm, @metadata_dev, @data_dev,
                   :block_size => k(32),
                   :format => true, :data_size => meg(128),
                   :policy => Policy.new('mq'))
  end

  # FIXME: non deterministic, depends on tick intervals
  def prepare_populated_cache_via_kernel()
    status = nil

    stack = standard_stack()
    stack.activate do |stack|
      50.times {wipe_device(stack.cache, 640)}
      status = CacheStatus.new(stack.cache)
      assert(status.residency > 0)
    end

    status
  end

  #--------------------------------

  define_test :residency_is_persisted do
    s1 = prepare_populated_cache_via_kernel()

    stack = standard_stack()
    stack.opts[:format] = false
    stack.activate do |stack|
      s2 = CacheStatus.new(stack.cache)
      assert_equal(s1.residency, s2.residency)
    end
  end
end

#----------------------------------------------------------------
