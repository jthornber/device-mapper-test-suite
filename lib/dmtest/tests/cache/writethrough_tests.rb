require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/cache_utils'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_policy'
require 'dmtest/tests/cache/fio_subvolume_scenario'
require 'tempfile'

#----------------------------------------------------------------

class WriteThroughTests < ThinpTestCase
  include FioSubVolumeScenario
  include Utils
  include CacheUtils
  include DiskUnits
  extend TestUtils

  def fio(dev)
    do_fio(dev, :ext4,
           :outfile => AP("fio_dm_cache.out"),
           :cfgfile => LP("tests/cache/database-funtime.fio"))
  end

  define_test :fio_with_writethrough do
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :policy => Policy.new('smq', :migration_threshold => 10240),
                           :cache_size => meg(128),
                           :block_size => k(32),
                           :data_size => gig(16),
                           :io_mode => :writethrough)
    stack.activate do |stack|
      fio(stack.cache)
      status = CacheStatus.new(stack.cache)
      assert_equal(status.nr_dirty, 0)
    end
  end

  define_test :clean_after_crash do
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :policy => Policy.new('smq', :migration_threshold => 10240),
                           :cache_size => meg(128),
                           :block_size => k(32),
                           :data_size => gig(16),
                           :io_mode => :writethrough)
                           
    stack.activate_support_devs do |data, metadata|
      stack.prepare_populated_cache(:dirty_percentage => 100)
      stack.activate_top_level do |stack|
        fio(stack.cache)
        wait_for_all_clean(stack.cache)
      end
    end

    stack.activate do |stack|
      status = CacheStatus.new(stack.cache)
      assert_equal(status.nr_dirty, 0)
    end
  end
end

#----------------------------------------------------------------
