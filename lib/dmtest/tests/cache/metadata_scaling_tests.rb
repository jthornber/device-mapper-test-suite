require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/pool-stack'
require 'dmtest/tags'
require 'dmtest/test-utils'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/cache_policy'
require 'dmtest/thinp-test'
require 'dmtest/tvm.rb'
require 'dmtest/utils'

require 'rspec/expectations'

#----------------------------------------------------------------

class MetadataScalingTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  include DMThinUtils
  include CacheUtils
  extend TestUtils

  POLICY_NAMES = %w(mq smq)

  def setup
    super
    @data_block_size = k(32)
    @cache_blocks = 1024
  end

  #--------------------------------

  # FIXME: add some assertions

  define_test :metadata_use_restored do
    data_size = gig(1)
    block_size = k(64)

    [[1024, 12], [2048, 15], [4096, 21], [8192, 33], [16384, 57]].each do |cache_blocks, expected_metadata_use|
      s = CacheStack.new(@dm, @metadata_dev, @data_dev,
                         :data_size => gig(4),
                         :block_size => block_size,
                         :cache_size => cache_blocks * block_size)
      s.activate_support_devs do
        s.prepare_populated_cache(:dirty_percentage => 100)
        s.activate_top_level do
          status = CacheStatus.new(s.cache)
          status.residency.should == cache_blocks
          status.md_used.should == expected_metadata_use
          STDERR.puts "cache_blocks #{cache_blocks}: #{status.md_used}/#{status.md_total}"
        end
      end
    end
  end

  def metadata_use_kernel(policy)
    data_size = gig(1)
    block_size = k(64)
    data_blocks = data_size / block_size

    [[1024, 9], [2048, 11], [4096, 15], [8192, 23], [16384, 39]].each do |cache_blocks, expected_metadata_use|
      s = CacheStack.new(@dm, @metadata_dev, @data_dev,
                         :data_size => gig(4),
                         :block_size => block_size,
                         :cache_size => cache_blocks * block_size,
                         :policy => Policy.new(policy, :migration_threshold => 1024000))
      s.activate do
        wipe_device(s.cache)

        status = CacheStatus.new(s.cache)
        status.md_used.should == expected_metadata_use

        STDERR.puts "cache_blocks #{cache_blocks}: #{status.md_used}/#{status.md_total}"
      end
    end
  end

  define_tests_across(:metadata_use_kernel, POLICY_NAMES)
end

#----------------------------------------------------------------
