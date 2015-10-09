require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/pool-stack'
require 'dmtest/test-utils'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/cache_policy'
require 'dmtest/thinp-test'
require 'dmtest/tvm.rb'
require 'dmtest/utils'

require 'rspec/expectations'
require 'thread'

#----------------------------------------------------------------

class DiscardTests < ThinpTestCase
  include GitExtract
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

  def with_standard_cache(opts = Hash.new, &block)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      block.call(stack.cache)
    end
  end

  def random_discard(dev, nr_sectors)
    b = rand(nr_sectors)
    e = [rand(nr_sectors), nr_sectors - b].min
    dev.discard(b, e)
  end

  #--------------------------------

  define_test :discard_with_concurrent_io do
    origin_size = gig(4)
    test_duration = 20

    with_standard_cache(:cache_size => meg(256),
                        :format => true,
                        :block_size => 512,
                        :data_size => origin_size,
                        :policy => Policy.new('mq')) do |cache|
      tids = []
      lock = Mutex.new

      # Discard thread
      tids << Thread.new do
        loop do
          if lock.try_lock
            random_discard(cache, origin_size)
          else
            break
          end
        end
      end

      # DT thread
      tids << Thread.new do
        dt_device(cache)
      end

      lock.lock
      tids.each {|t| t.join}
    end
  end

  define_test :discard_out_of_bounds do
    
    origin_size = gig(4) + 8
    with_standard_cache(:cache_size => meg(256),
                        :format => true,
                        :block_size => 512,
                        :data_size => origin_size,
                        :policy => Policy.new('mq')) do |cache|
      cache.discard(12, origin_size + gig(1))
    end
  end
end

#----------------------------------------------------------------
