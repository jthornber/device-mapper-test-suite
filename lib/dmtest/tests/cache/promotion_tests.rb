require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/cache_policy'
require 'dmtest/blktrace'

require 'rspec/expectations'

#----------------------------------------------------------------

#
# These tests aren't reliable for a couple of reasons:
#
# i)  mq's sequential io logic thwarts dd for large io
# ii) when issuing a read of a single block, block core reads more
#     than that, *without* setting the READA flag
#
# However they're useful for debugging policies, so I'm leaving them in.
#
class PromotionsBase < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  include CacheUtils
  extend TestUtils
  include BlkTrace

  def setup
    super
    @data_block_size = k(32)
    @cache_blocks = 1024
  end

  #--------------------------------

  # A discarded device should send writes straight to the cache.  No
  # need to hit a block multiple times.
  def check_promotions_to_a_discarded_device_occur(nr_blocks, expected_promotions)
    s = make_stack(:data_size => gig(1),
                   :block_size => k(32),
                   :cache_blocks => nr_blocks,
                   :io_mode => :writeback,
                   :policy => Policy.new('mq', :migration_threshold => gig(1)))

    s.activate do
      s.cache.discard(0, dev_size(s.cache))
      wipe_device(s.cache, k(32) * nr_blocks)

      status = CacheStatus.new(s.cache)
      status.promotions.should == expected_promotions
    end
  end

  def check_promotions_to_a_cold_cache_occur_writes(nr_blocks, expected_promotions)
    s = make_stack(:data_size => gig(1),
                   :block_size => k(32),
                   :cache_blocks => nr_blocks,
                   :io_mode => :writeback,
                   :policy => Policy.new('mq', :migration_threshold => gig(1)))

    s.activate do
      50.times do
        wipe_device(s.cache, k(32) * nr_blocks)
      end

      status = CacheStatus.new(s.cache)
      status.promotions.should >= expected_promotions
    end
  end

  def check_promotions_to_a_cold_cache_occur_reads(nr_blocks, expected_promotions)
    status = nil

    s = make_stack(:data_size => gig(1),
                   :block_size => k(32),
                   :cache_blocks => nr_blocks,
                   :io_mode => :writeback,
                   :policy => Policy.new('mq', :migration_threshold => gig(1)))

    s.activate_support_devs do
      s.activate_top_level do
        50.times do
          read_device_to_null(s.cache, k(32) * nr_blocks)
        end

        status = CacheStatus.new(s.cache)
      end

      status.promotions.should == expected_promotions
    end
  end


  def check_promotions_to_a_warm_cache_occur_writes(nr_blocks, expected_promotions)
    cache_len = nr_blocks * k(32)

    s = make_stack(:data_size => gig(1),
                   :block_size => k(32),
                   :cache_blocks => nr_blocks,
                   :io_mode => :writeback,
                   :policy => Policy.new('mq', :migration_threshold => gig(1)))

    # warm the cache
    s.activate do
      50.times do
        ProcessControl.run("dd seek=#{cache_len} if=/dev/zero of=#{s.cache.path} bs=512 count=#{cache_len}")
      end
    end

    # try and trigger some promotions
    s.activate do
      50.times do
        wipe_device(s.cache, k(32) * nr_blocks)
      end

      status = CacheStatus.new(s.cache)
      status.promotions.should >= expected_promotions
    end
  end

  def check_promotions_to_a_warm_cache_occur_reads(nr_blocks, expected_promotions)
    cache_len = nr_blocks * k(32)

    s = make_stack(:data_size => gig(1),
                   :block_size => k(32),
                   :cache_blocks => nr_blocks,
                   :io_mode => :writeback,
                   :policy => Policy.new('mq', :migration_threshold => gig(1)))

    # warm the cache
    s.activate do
      50.times do
        ProcessControl.run("dd seek=#{cache_len} if=/dev/zero of=#{s.cache.path} bs=512 count=#{cache_len}")
      end
    end

    # try and trigger some promotions
    s.activate do
      50.times do
        read_device_to_null(s.cache, k(32) * nr_blocks)
      end

      status = CacheStatus.new(s.cache)
      status.promotions.should >= expected_promotions
    end
  end
end

#----------------------------------------------------------------

class SingleBlockPromotionTests < PromotionsBase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  include CacheUtils
  extend TestUtils

  # A discarded device should send writes straight to the cache.  No
  # need to hit a block multiple times.
  def test_promotions_to_a_discarded_device_occur
    check_promotions_to_a_discarded_device_occur(1, 1)
  end

  def test_promotions_to_a_cold_cache_occur_writes
    check_promotions_to_a_cold_cache_occur_writes(1, 1)
  end

  def test_promotions_to_a_cold_cache_occur_reads
    check_promotions_to_a_cold_cache_occur_reads(1, 1)
  end


  def test_promotions_to_a_warm_cache_occur_writes
    check_promotions_to_a_warm_cache_occur_writes(1, 1)
  end

  def test_promotions_to_a_warm_cache_occur_reads
    check_promotions_to_a_warm_cache_occur_reads(1, 1)
  end
end

#----------------------------------------------------------------

class MultiBlockPromotionTests < PromotionsBase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  include CacheUtils
  extend TestUtils

  def setup
    super
    @nr_blocks = 100
  end

  # A discarded device should send writes straight to the cache.  No
  # need to hit a block multiple times.
  def test_promotions_to_a_discarded_device_occur
    check_promotions_to_a_discarded_device_occur(@nr_blocks, @nr_blocks)
  end

  def test_promotions_to_a_cold_cache_occur_writes
    check_promotions_to_a_cold_cache_occur_writes(@nr_blocks, @nr_blocks)
  end

  def test_promotions_to_a_cold_cache_occur_reads
    check_promotions_to_a_cold_cache_occur_reads(@nr_blocks, @nr_blocks)
  end


  def test_promotions_to_a_warm_cache_occur_writes
    check_promotions_to_a_warm_cache_occur_writes(@nr_blocks, @nr_blocks)
  end

  def test_promotions_to_a_warm_cache_occur_reads
    check_promotions_to_a_warm_cache_occur_reads(@nr_blocks, @nr_blocks)
  end
end

#----------------------------------------------------------------
