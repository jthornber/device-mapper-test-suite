require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/cache_policy'

require 'rspec/expectations'

#----------------------------------------------------------------

class PassthroughTests < ThinpTestCase
  include GitExtract
  include Utils
  include DiskUnits
  include CacheUtils
  extend TestUtils

  def setup
    super
    @data_block_size = k(32)
    @cache_blocks = 1024
  end

  #--------------------------------

  define_test :passthrough_never_promotes do
    s = make_stack(:data_size => gig(1),
                   :io_mode => :passthrough,
                   :block_size => k(64))
    s.activate do
      100.times {wipe_device(s.cache, 640)}

      status = CacheStatus.new(s.cache)
      assert_equal(0, status.promotions)
      assert_equal(0, status.residency)
    end
  end

  define_test :passthrough_demotes_writes do
    s = make_stack(:format => false,
                   :io_mode => :passthrough,
                   :block_size => k(64))
    s.activate_support_devs do
      s.prepare_populated_cache()

      s.activate_top_level do
        wipe_device(s.cache)

        status = CacheStatus.new(s.cache)
        assert_equal(0, status.residency)
      end
    end
  end

  define_test :passthrough_does_not_demote_reads do
    s = make_stack(:format => false,
                   :io_mode => :passthrough,
                   :block_size => k(64))
    s.activate_support_devs do
      s.prepare_populated_cache()
      s.activate_top_level do
        read_device_to_null(s.cache)

        status = CacheStatus.new(s.cache)
        assert_equal(@cache_blocks, status.residency)
      end
    end
  end

  define_test :passthrough_fails_with_dirty_blocks do
    s = make_stack(:format => false,
                   :io_mode => :passthrough,
                   :block_size => k(64))
    s.activate_support_devs do
      s.prepare_populated_cache(:dirty_percentage => 100)
      expect do
        s.activate_top_level
      end.to raise_error
    end
  end
end

#----------------------------------------------------------------
