require 'config'
require 'dmtest/blktrace'
require 'dmtest/disk-units'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

class ReadOnlyMetadataTests < ThinpTestCase
  include DiskUnits
  include Tags
  include TinyVolumeManager
  include Utils

  def test_with_ro_dev_works
    tvm = VM.new

    tvm.add_allocation_volume(@metadata_dev, 0, dev_size(@metadata_dev))
    tvm.add_volume(linear_vol('metadata', meg(20)))

    # now we open it read-only, expecting to be unable to create a rw pool
    with_ro_dev(tvm.table('metadata')) do |metadata|
      expect {wipe_device(metadata)}.to raise_error(ExitError)
    end
  end

  # This test fails because the kernel doesn't respect the ro flag on
  # the metadata device.  block/dm core changes required before this
  # will be fixed.
  def _test_rw_pool_fails_with_ro_metadata
    tvm = VM.new

    tvm.add_allocation_volume(@metadata_dev, 0, dev_size(@metadata_dev))
    tvm.add_volume(linear_vol('metadata', meg(20)))

    # First we format a pool
    with_dev(tvm.table('metadata')) do |metadata|
      stack = PoolStack.new(@dm, @data_dev, metadata, :data_size => gig(2))
      stack.activate {|pool|}
    end

    # now we open it read-only, expecting to be unable to create a rw pool
    with_ro_dev(tvm.table('metadata')) do |metadata|
      stack = PoolStack.new(@dm, @data_dev, metadata, :data_size => gig(2))
      expect do
        stack.activate do |pool|
          with_new_thin(pool, @volume_size, 0) do |thin|
            wipe_device(thin)
          end
        end
      end.to raise_error
    end
  end

  def test_ro_pool_succeeds_with_ro_metadata
    tvm = VM.new

    tvm.add_allocation_volume(@metadata_dev, 0, dev_size(@metadata_dev))
    tvm.add_volume(linear_vol('metadata', meg(20)))

    # First we format a pool, and create a thin in it
    with_dev(tvm.table('metadata')) do |metadata|
      stack = PoolStack.new(@dm, @data_dev, metadata, :data_size => gig(2))
      stack.activate do |pool|
        with_new_thin(pool, @volume_size, 0) do |thin|
          wipe_device(thin)
        end
      end
    end

    # now we open it read-only, expecting to be unable to create a rw pool
    with_ro_dev(tvm.table('metadata')) do |metadata|
      stack = PoolStack.new(@dm, @data_dev, metadata, :data_size => gig(2), :read_only => true)
      stack.activate do |pool|
        with_thin(pool, @volume_size, 0) do |thin|
          # already fully provisioned, so we can access it
          wipe_device(thin)
        end
      end
    end
  end
end

#----------------------------------------------------------------
