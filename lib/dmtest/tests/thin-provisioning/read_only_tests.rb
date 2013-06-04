require 'config'
require 'dmtest/blktrace'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

class ReadOnlyTests < ThinpTestCase
  include Tags
  include TinyVolumeManager
  include Utils

  def setup
    super

    # I'm assuming you have set up 2G ramdisks (ramdisk_size=2097152 on boot)
    @data_dev = '/dev/ram1'

    if !$wiped_ramdisk
      wipe_device(@data_dev)
      $wiped_ramdisk = true
    end

    @size = 2097152 * 2         # sectors
    @volume_size = 1900000
    @data_block_size = 2 * 1024 * 8 # 8 M
  end

  def test_create_read_only
    # we have to create a valid metadata dev first
    with_standard_pool(@size) do |pool|
    end

    # now we open it read-only
    with_standard_pool(@size, :read_only => true) do |pool|
    end
  end

  def test_can_access_fully_mapped_device
    # we have to create a valid metadata dev first
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)
      end
    end

    # now we open it read-only
    with_standard_pool(@size, :read_only => true) do |pool|
      with_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)
      end
    end
  end

  def test_cant_provision_new_blocks
    # we have to create a valid metadata dev first
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
      end
    end

    # now we open it read-only
    with_standard_pool(@size, :read_only => true) do |pool|
      with_thin(pool, @volume_size, 0) do |thin|
        assert_raise(ExitError) do
          wipe_device(thin)
        end
      end
    end
  end

  def test_cant_create_new_thins
    # we have to create a valid metadata dev first
    with_standard_pool(@size) do |pool|
    end

    # now we open it read-only
    with_standard_pool(@size, :read_only => true) do |pool|
      assert_raise(ExitError) do
        with_new_thin(pool, @volume_size, 0) do |thin|
        end
      end
    end
  end

  def test_cant_delete_thins
    # we have to create a valid metadata dev first
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
      end
    end

    # now we open it read-only
    with_standard_pool(@size, :read_only => true) do |pool|
      assert_raise(ExitError) do
        pool.message(0, "delete 0");
      end
    end
  end

  def test_commit_failure_causes_fallback
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |t1, t2|
      end
    end

    # Overlay the metadata dev with a linear mapping, so we can swap
    # it for an error target in a bit.
    tvm = VM.new
    tvm.add_allocation_volume(@metadata_dev, 0, dev_size(@metadata_dev))
    tvm.add_volume(linear_vol('metadata', dev_size(@metadata_dev)))

    md_table = tvm.table('metadata')
    with_dev(md_table) do |md|
      with_dev(Table.new(ThinPoolTarget.new(@size, md, @data_dev, 128, 1))) do |pool|
        with_thins(pool, @volume_size, 0, 1) do |t1, t2|
          wipe_device(t1)

          reload_with_error_target(md)

          # knock out the thin check on deactivation, the md device
          # isn't accessible now. (Isn't Ruby great).
          def pool.post_remove_check
          end

          assert_raise(ExitError) do
            wipe_device(t2)
          end

          # we have to put the md device back so that the automatic
          # thin_check passes.
          md.pause {md.load(md_table)}

          status = PoolStatus.new(pool)
          assert(status.fail)
        end
      end
    end
  end
end
