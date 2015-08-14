require 'dmtest/blktrace'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/test-utils'

#----------------------------------------------------------------

class ReadOnlyTests < ThinpTestCase
  include Tags
  include TinyVolumeManager
  include Utils
  extend TestUtils

  def setup
    super

    @size = 2097152 * 2         # sectors
    @volume_size = 1900000
    @data_block_size = 2 * 1024 * 8 # 8 M
  end

  define_test :create_read_only do
    # we have to create a valid metadata dev first
    with_standard_pool(@size) do |pool|
    end

    # now we open it read-only
    with_standard_pool(@size, :read_only => true, :format => false) do |pool|
    end
  end

  define_test :can_access_fully_mapped_device do
    # we have to create a valid metadata dev first
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)
      end
    end

    # now we open it read-only
    with_standard_pool(@size, :read_only => true, :format => false) do |pool|
      with_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)
      end
    end
  end

  define_test :can_read_unprovisioned_regions do
    # we have to create a valid metadata dev first
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
      end
    end

    # now we open it read-only
    with_standard_pool(@size, :read_only => true, :format => false) do |pool|
      with_thin(pool, @volume_size, 0) do |thin|
        read_device_to_null(thin)
      end
    end
  end

  define_test :cant_provision_new_blocks do
    # we have to create a valid metadata dev first
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
      end
    end

    # now we open it read-only
    with_standard_pool(@size, :read_only => true, :format => false, :error_if_no_space => true) do |pool|
      with_thin(pool, @volume_size, 0) do |thin|
        assert_raise(ExitError) do
          wipe_device(thin)
        end
      end
    end
  end

  define_test :cant_create_new_thins do
    # we have to create a valid metadata dev first
    with_standard_pool(@size) do |pool|
    end

    # now we open it read-only
    with_standard_pool(@size, :read_only => true, :format => false) do |pool|
      assert_raise(ExitError) do
        with_new_thin(pool, @volume_size, 0) do |thin|
        end
      end
    end
  end

  define_test :cant_delete_thins do
    # we have to create a valid metadata dev first
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
      end
    end

    # now we open it read-only
    with_standard_pool(@size, :read_only => true, :format => false) do |pool|
      assert_raise(ExitError) do
        pool.message(0, "delete 0");
      end
    end
  end

  define_test :commit_failure_causes_fallback do
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |t1, t2|
      end
    end

    # Overlay the metadata dev with a linear mapping, so we can swap
    # it for an error target in a bit.
    tvm = VM.new
    tvm.add_allocation_volume(@metadata_dev)
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
