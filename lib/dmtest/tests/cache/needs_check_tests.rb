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
  extend TestUtils

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

  def commit_failure_sets_needs_check(&make_bad_md_table)
    superblock_size = k(4)
    metadata_size = meg(4)
    metadata_body_size = metadata_size - superblock_size

    tvm = VM.new
    tvm.add_allocation_volume(@metadata_dev)
    tvm.add_volume(linear_vol('metadata_superblock', superblock_size))
    tvm.add_volume(linear_vol('metadata_body', metadata_body_size))
    tvm.add_volume(linear_vol('ssd', meg(512)))
    tvm.add_volume(linear_vol('origin', gig(1)))

    with_devs(tvm.table('metadata_superblock'),
              tvm.table('metadata_body'),
              tvm.table('ssd'),
              tvm.table('origin')) do |metadata_superblock, metadata_body, ssd, origin|

      good_md_table = Table.new(LinearTarget.new(superblock_size, metadata_superblock, 0),
                                LinearTarget.new(metadata_body_size, metadata_body, 0))
      bad_md_table = make_bad_md_table.call(metadata_superblock, metadata_body)

      wipe_device(metadata_superblock)

      with_dev(good_md_table) do |metadata|
        table = Table.new(CacheTarget.new(dev_size(origin), metadata, ssd, origin,
                                          @data_block_size, [], 'smq', {}))

        with_dev(table) do |cache|
          wipe_device(cache, 128)

          cache.pause do
            metadata.pause do
              metadata.load(bad_md_table)
            end
          end

          wipe_device(cache, 256)

          cache.pause {}        # the suspend will trigger a commit, which will fail
          assert(read_only_or_fail_mode?(cache))

          # Put the metadata dev back so cache_check completes
          metadata.pause do
            metadata.load(good_md_table)
          end
        end
      end

      with_dev(good_md_table) do |metadata|
        table = Table.new(CacheTarget.new(dev_size(origin), metadata, ssd, origin,
                                          @data_block_size, [], 'smq', {}))
        
        begin
          with_dev(table) do |cache|
            # We shouldn't be able to bring up the cache because the
            # needs_check flag is set.
            assert(false)
          end
        rescue
        end

        ProcessControl.run("cache_check --clear-needs-check-flag #{metadata}")

        # Now we should be able to run in write mode
        with_dev(table) do |cache|
          assert(write_mode?(cache))
        end
      end
    end
  end

  define_test :commit_failure_sets_needs_check_error_target do
    commit_failure_sets_needs_check do |metadata_superblock, metadata_body|
      Table.new(LinearTarget.new(dev_size(metadata_superblock), metadata_superblock, 0),
                ErrorTarget.new(dev_size(metadata_body)))
    end
  end

  define_test :commit_failure_sets_needs_check_flakey_target do
    commit_failure_sets_needs_check do |metadata_superblock, metadata_body|
      Table.new(LinearTarget.new(dev_size(metadata_superblock), metadata_superblock, 0),
                FlakeyTarget.new(dev_size(metadata_body), metadata_body, 0, 0, 60))
    end
  end
end

#----------------------------------------------------------------
