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
                   :block_size => k(64),
                   :format => true, :data_size => meg(128),
                   :policy => Policy.new('mq'))
  end

  def prepare_populated_cache()
    status = nil

    stack = standard_stack()
    stack.activate do |stack|
      20.times {wipe_device(stack.cache, 1)}
      status = CacheStatus.new(stack.cache)
      pp status
      assert(status.residency > 0) # FIXME: failing
    end

    status
  end

  #--------------------------------

  def test_residency_is_persisted
    s1 = prepare_populated_cache()

    stack = standard_stack()
    stack.opts[:format] = false
    stack.activate do |stack|
      s2 = CacheStatus.new(stack.cache)
      assert_equal(s1.residency, s2.residency)
    end
  end
end

#----------------------------------------------------------------
