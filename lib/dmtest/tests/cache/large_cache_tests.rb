require 'dmtest/cache-status'
require 'dmtest/cache_policy'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/disk-units'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/pool-stack'
require 'dmtest/test-utils'
require 'dmtest/thinp-test'
require 'dmtest/tvm.rb'
require 'dmtest/utils'

require 'rspec/expectations'

#----------------------------------------------------------------

class LargeConfigTests < ThinpTestCase
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

  def with_big_stack(&block)
    # create two pools, one of fast ssd storage, and one of spindle
    # storage
    fast_tvm = TinyVolumeManager::VM.new
    fast_tvm.add_allocation_volume(@metadata_dev)
    fast_tvm.add_volume(linear_vol('fast_md', meg(128)))
    fast_tvm.add_volume(linear_vol('slow_md', meg(128)))
    fast_tvm.add_volume(linear_vol('fast_data', fast_tvm.free_space))

    with_devs(fast_tvm.table('fast_md'),
              fast_tvm.table('slow_md'),
              fast_tvm.table('fast_data')) do |fast_md, slow_md, fast_data|

      fast_stack = PoolStack.new(@dm, fast_data, fast_md, :data_size => dev_size(fast_data))
      slow_stack = PoolStack.new(@dm, @data_dev, slow_md, :data_size => dev_size(@data_dev))

      fast_stack.activate do |fast_pool|
        slow_stack.activate do |slow_pool|
          with_new_thin(fast_pool, tera(4), 0) do |fast_storage|
            with_new_thin(slow_pool, tera(48), 0) do |slow_storage|
              
              cache_stack = CacheStack.new(@dm, fast_storage, slow_storage,
                                           :format => true, :block_size => k(32))
              cache_stack.activate_support_devs do
                cache_stack.prepare_populated_cache
                cache_stack.activate do
                  block.call(cache_stack)
                end
              end
            end
          end
        end
      end
    end
  end

  #--------------------------------

  define_test :large_stack do
    with_big_stack do |stack|
      fs = FS::file_system(:xfs, stack.cache)
      fs.format

      status = CacheStatus.new(stack.cache)
      pp status
    end
  end

  # Designed to be run on really big systems that really do have the
  # backing store
  define_test :dt_in_chunks do
    promotions = 0

    s = make_stack(:format => true,
                   :metadata_size => meg(512), # you may need to increase this (I have only 1G of SSD)
                   :block_size => meg(4),
                   :cache_size => :all,
                   :data_size => :all,
                   :policy => Policy.new('mq',
                                         :migration_threshold => 1000000,
                                         :read_promote_adjustment => 0,
                                         :write_promote_adjustment => 0,
                                         :discard_promote_adjustment => 0))
    s.activate do
      s.cache.discard(0, dev_size(s.cache))

      step = gig(1)
      tvm = TinyVolumeManager::VM.new
      tvm.add_allocation_volume(s.cache)

      volumes = []

      n = 0
      while tvm.free_space > 0
        name = "chunk_#{n}"
        tvm.add_volume(linear_vol(name, [step, tvm.free_space].min))
        volumes << name
        n += 1
      end

      volumes.each do |vol_name|
        with_dev(tvm.table(vol_name)) do |linear|
          report_time("dt #{vol_name}", STDERR) do
            dt_device(linear)
          end
        end

        status = CacheStatus.new(s.cache)
        promotions = status.promotions - promotions
        STDERR.puts "residency #{status.residency}, promotions this cycle #{promotions}"
      end
    end
  end

  #--------------------------------

  def error_table(nr_sectors)
    Table.new(ErrorTarget.new(nr_sectors))
  end

  def cache_table(md, fast_dev, slow_dev)
    Table.new(CacheTarget.new(dev_size(slow_dev), md, fast_dev, slow_dev,
                              k(32), [], 'mq', {}))
  end

  # If I run with 4G ram then the OOM killer kicks in.  14G is enough
  # memory to reproduce the bug.
  define_test :bug_1080894 do
    fast_size = 4504174592
    origin_size = 6442450944

    # we use a real metadata area, and the error target for the fast
    # and slow devices.
    with_devs(error_table(fast_size),
              error_table(origin_size)) do |fast_dev, slow_dev|
      wipe_device(@metadata_dev, 8);

      with_dev(cache_table(@metadata_dev, fast_dev, slow_dev)) do |cache|
        STDERR.puts "created cache device\n";
      end
    end
  end
end

#----------------------------------------------------------------
