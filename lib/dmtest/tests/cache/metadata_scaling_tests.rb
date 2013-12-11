require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/pool-stack'
require 'dmtest/tags'
require 'dmtest/test-utils'
require 'dmtest/tests/cache/cache_stack'
require 'dmtest/tests/cache/cache_utils'
require 'dmtest/tests/cache/policy'
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

  def setup
    super
    @data_block_size = k(32)
    @cache_blocks = 1024
  end

  #--------------------------------

  # FIXME: add some assertions

  def test_metadata_use_restored
    data_size = gig(1)
    block_size = k(32)
    data_blocks = data_size / block_size
    cache_blocks = 1024

    while cache_blocks < data_blocks do
      s = make_stack(:data_size => gig(4),
                     :block_size => k(32),
                     :cache_blocks => cache_blocks)
      s.activate_support_devs do
        s.prepare_populated_cache(:dirty_perccentage => 100)
        s.activate_top_level do
          status = cachestatus.new(s.cache)

          stderr.puts "cache_blocks #{cache_blocks}: #{status.md_used}/#{status.md_total}"
        end
      end

      cache_blocks *= 2
    end
  end

  def test_metadata_use_kernel
    big = 10240000
    data_size = gig(1)
    block_size = k(32)
    data_blocks = data_size / block_size
    cache_blocks = 1024

    while cache_blocks < data_blocks do
      s = make_stack(:data_size => gig(4),
                     :block_size => k(32),
                     :cache_blocks => cache_blocks,
                     :policy => Policy.new('mq',
                                           :migration_threshold => big,
                                           :sequential_threshold => big,
                                           :read_promote_adjustment => 0,
                                           :write_promote_adjustment => 0,
                                           :discard_promote_adjustment => 0))
      s.activate do
        1.times do
          wipe_device(s.cache)
          STDERR.puts "wiped"
        end

        status = CacheStatus.new(s.cache)

        # check we have 100% residency
        status.residency.should == cache_blocks

        stderr.puts "cache_blocks #{cache_blocks}: #{status.md_used}/#{status.md_total}"
      end

      cache_blocks *= 2
    end
    
  end
end

#----------------------------------------------------------------
