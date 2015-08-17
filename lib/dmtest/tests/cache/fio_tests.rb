require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_policy'
require 'dmtest/tests/cache/fio_subvolume_scenario'

#----------------------------------------------------------------

class FIOTests < ThinpTestCase
  include FioSubVolumeScenario
  include Utils
  include DiskUnits
  extend TestUtils

  POLICY_NAMES = %w(mq smq)

  def setup
    super
    @data_block_size = meg(1)
  end

  def do_fio__(opts)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      do_fio(stack.cache, :ext4,
             :outfile => AP("fio_dm_cache.out"),
             :cfgfile => LP("tests/cache/database-funtime.fio"))
      pp CacheStatus.new(stack.cache)
    end
  end

  def fio_across_cache_size(policy_name)
    [512, 1024, 2048, 4096, 8192, 8192 + 1024].each do |cache_size|
      report_time("cache size = #{cache_size}, policy = #{policy_name}", STDERR) do
        do_fio__(:policy => Policy.new(policy_name, :migration_threshold => 1024),
                 :cache_size => meg(cache_size),
                 :block_size => k(32),
                 :data_size => gig(16))
      end
    end
  end

  define_tests_across(:fio_across_cache_size, POLICY_NAMES)

  #--------------------------------

  def origin_same_size_as_ssd(policy_name)
    report_time("fio", STDERR) do
      do_fio__(:policy => Policy.new(policy_name, :migration_threshold => 1024),
               :metadata_size => meg(128),
               :cache_size => gig(10),
               :block_size => k(32),
               :data_size => gig(10))
    end
  end

  define_tests_across(:origin_same_size_as_ssd, POLICY_NAMES)
end

#----------------------------------------------------------------
