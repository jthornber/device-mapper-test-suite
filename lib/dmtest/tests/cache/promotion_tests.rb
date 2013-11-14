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

class PromotionTests < ThinpTestCase
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

  # A discarded device should send writes straight to the cache.  No
  # need to hit a block multiple times.
  def test_promotions_to_a_discarded_device_occur
    s = make_stack(:data_size => gig(1),
                   :block_size => k(32),
                   :cache_blocks => 100,
                   :io_mode => :writeback,
                   :policy => Policy.new('mq', :migration_threshold => gig(1)))

    s.activate do
      s.cache.discard(0, dev_size(s.cache))

      nr_promotions = 100
      wipe_device(s.cache, k(32) * nr_promotions)

      status = CacheStatus.new(s.cache)
      status.promotions.should == nr_promotions
    end
  end

  def test_promotions_to_a_cold_cache_occur_writes
    s = make_stack(:data_size => gig(1),
                   :block_size => k(32),
                   :cache_blocks => 100,
                   :io_mode => :writeback,
                   :policy => Policy.new('mq', :migration_threshold => gig(1)))

    s.activate do
      nr_promotions = 100

      10.times do
        wipe_device(s.cache, k(32) * nr_promotions)
      end

      status = CacheStatus.new(s.cache)
      status.promotions.should >= (nr_promotions / 4)
    end
  end

  def test_promotions_to_a_cold_cache_occur_reads
    s = make_stack(:data_size => gig(1),
                   :block_size => k(32),
                   :cache_blocks => 100,
                   :io_mode => :writeback,
                   :policy => Policy.new('mq', :migration_threshold => gig(1)))

    s.activate do
      nr_promotions = 100

      50.times do
        read_device_to_null(s.cache, k(32) * nr_promotions)
      end

      status = CacheStatus.new(s.cache)
      status.promotions.should >= (nr_promotions - 10)
    end
  end


  def test_promotions_to_a_warm_cache_occur_writes
    nr_promotions = 100
    cache_len = nr_promotions * k(32)

    s = make_stack(:data_size => gig(1),
                   :block_size => k(32),
                   :cache_blocks => nr_promotions,
                   :io_mode => :writeback,
                   :policy => Policy.new('mq', :migration_threshold => gig(1)))

    # warm the cache
    s.activate do
      10.times do
        ProcessControl.run("dd seek=#{cache_len} if=/dev/zero of=#{s.cache.path} bs=512 count=#{100}")
      end
    end

    # try and trigger some promotions
    s.activate do
      10.times do
        wipe_device(s.cache, k(32) * nr_promotions)
      end

      status = CacheStatus.new(s.cache)
      status.promotions.should >= (nr_promotions / 4)
    end
  end

  def test_promotions_to_a_warm_cache_occur_reads
    nr_promotions = 100
    cache_len = nr_promotions * k(32)

    s = make_stack(:data_size => gig(1),
                   :block_size => k(32),
                   :cache_blocks => nr_promotions,
                   :io_mode => :writeback,
                   :policy => Policy.new('mq', :migration_threshold => gig(1)))

    # warm the cache
    s.activate do
      10.times do
        ProcessControl.run("dd seek=#{cache_len} if=/dev/zero of=#{s.cache.path} bs=512 count=#{100}")
      end
    end

    # try and trigger some promotions
    s.activate do
      50.times do
        read_device_to_null(s.cache, k(32) * nr_promotions)
      end

      status = CacheStatus.new(s.cache)
      status.promotions.should >= (nr_promotions - 10)
    end
  end

end

#----------------------------------------------------------------
