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
require 'dmtest/tests/cache/cache_utils'
require 'dmtest/tests/cache/policy'

require 'rspec/expectations'

#----------------------------------------------------------------

class PassthroughTests < ThinpTestCase
  include GitExtract
  include Tags
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

  def test_passthrough_never_promotes
    s = make_stack(:data_size => gig(1),
                   :io_mode => :passthrough)
    s.activate do
      100.times {wipe_device(s.cache, 640)}

      status = CacheStatus.new(s.cache)
      assert_equal(0, status.promotions)
      assert_equal(0, status.residency)
    end
  end

  def test_passthrough_demotes_writes
    prepare_populated_cache()

    s = make_stack(:format => false,
                   :io_mode => :passthrough)
    s.activate do
      wipe_device(s.cache)

      status = CacheStatus.new(s.cache)
      assert_equal(0, status.residency)
    end
  end

  def test_passthrough_does_not_demote_reads
    prepare_populated_cache()

    s = make_stack(:format => false,
                   :io_mode => :passthrough)
    s.activate do
      read_device_to_null(s.cache)

      status = CacheStatus.new(s.cache)
      assert_equal(@cache_blocks, status.residency)
    end
  end

  def test_passthrough_fails_with_dirty_blocks
    prepare_populated_cache(:dirty_percentage => 100)

    s = make_stack(:format => false,
                   :io_mode => :passthrough)
    expect do
      s.activate
    end.to raise_error
  end
end

#----------------------------------------------------------------
