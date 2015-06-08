require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/disk-units'
require 'dmtest/thinp-test'
require 'timeout'
require 'dmtest/cache_stack'
require 'dmtest/cache_policy'

#----------------------------------------------------------------

class NeedsCheckTests < ThinpTestCase
  include Tags
  include Utils
  include TinyVolumeManager
  include DiskUnits

  def setup
    super
    @data_block_size = meg(1)
  end

  def read_only_or_fail_mode?(cache)
    status = CacheStatus.new(cache)
    status.fail || status.mode == :read_only
  end

  def read_only_mode?(cache)
    CacheStatus.new(cache).mode == :read_only
  end

  def write_mode?(pool)
    CacheStatus.new(pool).mode == :read_write
  end

  #--------------------------------

  def test_commit_failure_sets_needs_check
    tvm = VM.new
    tvm.add_allocation_volume(@metadata_dev)
    tvm.add_volume(linear_vol('metadata', meg(4)))
    tvm.add_volume(linear_vol('ssd', meg(512)))
    tvm.add_volume(linear_vol('origin', gig(1)))

    with_devs(tvm.table('metadata'), tvm.table('ssd'), tvm.table('origin')) do |metadata, ssd, origin|
      wipe_device(metadata, 8)

      table = Table.new(CacheTarget.new(dev_size(origin), metadata, ssd, origin,
                                        @data_block_size, [], 'smq', {}))

      with_dev(table) do |cache|
        wipe_device(cache, 128)

        begin
          cache.pause do
            # Establish flakey metadata.  We need the superblock to
            # remain working.
            superblock_size = 8
            flakey_table = Table.new(LinearTarget.new(8, @metadata_dev, 0),
                                     FlakeyTarget.new(dev_size(@metadata_dev) - superblock_size,
                                                      @metadata_dev, 8, 0, 60))
            metadata.pause do
              metadata.load(flakey_table)
            end
          end

          wipe_device(cache, 256)
          assert(read_only_or_fail_mode?(cache))
        ensure
          # Put the metadata dev back
          metadata.pause do
            metadata.load(tvm.table('metadata'))
          end
        end
      end

      # We can bring up the cache, but it will have immediately fallen
      # back to read_only mode.
      with_dev(table) do |cache|
        assert(read_only_mode?(cache))
      end

      # FIXME: use tools to clear needs_check mode
      #ProcessControl.run("cache_check --clear-needs-check-flag #{metadata}")

      ## Now we should be able to run in write mode
      #with_dev(table) do |cache|
      #  assert(write_mode?(cache))
      #end
    end
  end
end

#----------------------------------------------------------------
