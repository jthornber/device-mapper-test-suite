require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/pattern_stomper'
require 'dmtest/tags'
require 'dmtest/test-utils'
require 'dmtest/tests/cache/cache_stack'
require 'dmtest/tests/cache/cache_utils'
require 'dmtest/tests/cache/policy'
require 'dmtest/thinp-test'
require 'dmtest/tvm.rb'
require 'dmtest/utils'

require 'thinp_xml/cache_xml'

#----------------------------------------------------------------

# We use dm thin to siimulate the exernal storage.
class SanStack
  include DiskUnits
  include DMThinUtils

  attr_accessor :metadata_dev, :data_dev, :snaps

  def initialize(dm, data_dev, metadata_dev, data_block_size, nr_blocks)
    @dm = dm
    @data_dev = data_dev
    @data_block_size = data_block_size
    @nr_blocks = nr_blocks
    @metadata_dev = metadata_dev
    @nr_snaps = 0
  end

  def activate(&block)
    s = PoolStack.new(@dm, @data_dev, @metadata_dev, :data_block_size => @data_block_size)
    s.activate do |pool|
      @pool = pool
      with_new_thin(pool, thin_size, 0) do |thin|
        @thin = thin
        block.call(thin)
      end
    end
  end

  def thin_size
    @nr_blocks * @data_block_size
  end

  # must be activated
  def take_snapshot
    @thin.pause do
      @pool.message(0, "create_snap #{@nr_snaps + 1} #{@nr_snaps}")
      @nr_snaps += 1
      @thin.load(thin_table(@pool, thin_size, @nr_snaps))
    end
  end

  def rollback(snap_index)
    raise "unknown snap index" unless snap_index < @nr_snaps

    @thin.pause do
      @thin.load(thin_table(@pool, thin_size, snap_index))
    end
  end
end

#----------------------------------------------------------------

class InvalidationTests < ThinpTestCase
  include GitExtract
  include Tags
  include CacheUtils

  def setup
    super
    @data_block_size = k(32)
    @cache_blocks = 10
    @nr_blocks = 100
    @nr_snapshots = 20
  end

  #--------------------------------

  # This is the scenario driving the NetApp work
  def test_invalidation_works_on_rollback
    # reserve a bit of the metadata device for the thin pool metadata
    tvm = TinyVolumeManager::VM.new
    tvm.add_allocation_volume(@metadata_dev, 0, dev_size(@metadata_dev))
    tvm.add_volume(linear_vol('thin_metadata', meg(128)))
    tvm.add_volume(linear_vol('cache_metadata', meg(512)))

    with_devs(tvm.table('thin_metadata'),
              tvm.table('cache_metadata')) do |thin_md, cache_md|

      external_storage = SanStack.new(@dm, @data_dev, thin_md, @data_block_size, @nr_blocks)
      external_storage.activate do |vol|
        origin_stomper = PatternStomper.new(vol.path, @data_block_size, :needs_zero => false)
        origin_stomper.verify(0)

        s = CacheStack.new(@dm, cache_md, vol,
                           :format => true,
                           :cache_size => meg(256),
                           :block_size => @data_block_size,
                           :io_mode => :writethrough,
                           :policy => Policy.new('era+mq'))

        s.activate do |stack|
          cache_stomper = origin_stomper.fork(stack.cache.path)
          cache_stomper.verify(0)

          stack.cache.pause do
            stack.cache.message(0, "increment_era_counter 1")
            external_storage.take_snapshot
          end

          cache_stomper.stamp(10)
          cache_stomper.verify(0, 1)

          stack.with_io_mode(:passthrough) do
            cache_stomper.verify(1)

            stack.cache.pause do
              external_storage.rollback(0)
              stack.cache.message(0, "unmap_blocks_from_this_era_and_later 2")
            end
          end

          cache_stomper.verify(0)
        end
      end
    end
  end

  def test_external_storage_snap_and_rollback
    # reserve a bit of the metadata device for the thin pool metadata
    tvm = TinyVolumeManager::VM.new
    tvm.add_allocation_volume(@metadata_dev, 0, dev_size(@metadata_dev))
    tvm.add_volume(linear_vol('thin_metadata', meg(128)))
    tvm.add_volume(linear_vol('cache_metadata', meg(512)))

    with_dev(tvm.table('thin_metadata')) do |thin_md|

      external_storage = SanStack.new(@dm, @data_dev, thin_md, @data_block_size, @nr_blocks)
      external_storage.activate do |vol|
        stomper = PatternStomper.new(vol.path, @data_block_size, :needs_zero => false)

        external_storage.take_snapshot
        stomper.stamp(10)
        stomper.verify(0, 1)
        external_storage.take_snapshot
        stomper.stamp(20)
        stomper.verify(0, 2)
        external_storage.rollback(1)
        stomper.verify(0, 1)
        external_storage.rollback(0)
        stomper.verify(0)
      end
    end
  end
end

#----------------------------------------------------------------
