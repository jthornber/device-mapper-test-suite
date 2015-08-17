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
require 'dmtest/tests/cache/pool_cache_stack'
require 'pp'

#----------------------------------------------------------------

class DTTests < ThinpTestCase
  include Utils
  include DiskUnits
  extend TestUtils

  POLICY_NAMES = %w(mq smq)

  def setup
    super
    @data_block_size = meg(1)
  end

  #--------------------------------

  def dt_cache(policy)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :policy => Policy.new(policy, :migration_threshold => 1024),
                           :cache_size => meg(1024),
                           :block_size => k(32),
                           :data_size => gig(16))
    stack.activate do |stack|
      dt_device(stack.cache)
    end
  end

  define_tests_across(:dt_cache, POLICY_NAMES)

  #--------------------------------

  def dt_thin_snap(policy)
    data_size = gig(64)

    stack = PoolCacheStack.new(@dm, @metadata_dev, @data_dev,
                               { :policy => Policy.new(policy, :migration_threshold => 1024),
                                 :cache_size => meg(3072),
                                 :block_size => k(32),
                                 :data_size => data_size,
                                 :format => true
                               },
                               {
                                 :data_size => data_size,
                                 :block_size => meg(4),
                                 :zero => false,
                                 :format => true,
                                 :discard => true,
                                 :discard_passdown => true
                               })
    stack.activate do |pool|
      with_new_thin(pool, gig(16), 0) do |thin|
        dt_device(thin)
#        dt_device(thin)
#        verify_device(thin)

        with_new_snap(pool, gig(16), 1, 0, thin) do |snap|
          dt_device(thin)
#          dt_device(snap)
#          verify_device(thin)
#          verify_device(snap)
        end
      end
    end
  end

  define_tests_across(:dt_thin_snap, POLICY_NAMES)
end

#----------------------------------------------------------------
