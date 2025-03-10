require 'dmtest/blktrace'
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
  include BlkTrace
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
                        :discard_passdown => false,
                        :policy => Policy.new('mq')) do |cache|
      stopped = Concurrent::AtomicBoolean::new

      # Discard thread
      tid = Thread.new do
        while !stopped.true?
          random_discard(cache, origin_size)
        end
      end

      begin
        # Wait for DT to complete
        dt_device(cache)
      ensure
        stopped.make_true()
        tid.join
      end
    end
  end

  define_test :discard_out_of_bounds do
    origin_size = gig(4) + 8
    with_standard_cache(:cache_size => meg(256),
                        :format => true,
                        :block_size => 512,
                        :data_size => origin_size,
                        :policy => Policy.new('mq')) do |cache|
      expect {
        cache.discard(12, origin_size + gig(1))
      }.to raise_error(Errno::EINVAL)
    end
  end

  #--------------------------------

  def discard(dev, b, len)
    b_sectors = b * @data_block_size
    len_sectors = len * @data_block_size

    dev.discard(b_sectors, [len_sectors, @volume_size - b_sectors].min)
  end

  def stationary_cache(opts)
    opts[:policy] = Policy.new('cleaner');
    CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
  end

  define_test :discard_passed_to_origin do
    s = stationary_cache(:data_size => gig(4),
                         :cache_size => gig(1),
                         :block_size => 512)
    s.activate do |s|
      status = CacheStatus.new(s.cache)
      assert(!status.features.include?('no_discard_passdown'),
             'cache origin discard unsupported')

      traces, _ = blktrace(s.cache, s.origin) do
        discard(s.cache, 0, 1)
      end

      assert_discards(traces[0], 0, @data_block_size)
      assert_discards(traces[1], 0, @data_block_size)
    end
  end
end

#----------------------------------------------------------------
