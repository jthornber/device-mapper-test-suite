require 'dmtest/cache-status'
require 'dmtest/cache_policy'
require 'dmtest/cache_stack'
require 'dmtest/disk-units'
require 'dmtest/fs'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/tags'
require 'dmtest/test-utils'
require 'dmtest/thinp-test'
require 'dmtest/utils'

#----------------------------------------------------------------

class StackingTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  extend TestUtils

  MOUNT_DIR = './stacking-mount'

  # https://bugzilla.redhat.com/show_bug.cgi?id=1111748
  def test_cached_external_origin
    # Carve up some space
    origin_size = gig(4)

    fast_tvm = TinyVolumeManager::VM.new
    fast_tvm.add_allocation_volume(@metadata_dev)
    fast_tvm.add_volume(linear_vol('ssd', gig(2)))
    fast_tvm.add_volume(linear_vol('pool_md', gig(1)))

    slow_tvm = TinyVolumeManager::VM.new
    slow_tvm.add_allocation_volume(@data_dev)
    slow_tvm.add_volume(linear_vol('origin', origin_size))
    slow_tvm.add_volume(linear_vol('pool_data', gig(4)))

    # activate the low level devices
    with_devs(slow_tvm.table('origin'),
              fast_tvm.table('ssd'),
              fast_tvm.table('pool_md'),
              slow_tvm.table('pool_data')) do |origin, ssd, pool_md, pool_data|

      # cache the origin
      cache_stack = CacheStack.new(@dm, ssd, origin,
                                   :data_size => gig(4),
                                   :cache_size => meg(512),
                                   :block_size => 512)

      cache_stack.activate do |cache_stack|
        fs = FS::file_system(:xfs, cache_stack.cache)
        fs.format
        fs.with_mount(MOUNT_DIR) do
          ProcessControl.run("dd if=/dev/zero of=#{MOUNT_DIR}/ddfile bs=1M count=100")

          # We unmount because an external origin *must* be read only
        end

        pool_stack = PoolStack.new(@dm, pool_data, pool_md,
                                   :data_size => gig(4),
                                   :format => true)
        pool_stack.activate do |pool|
          with_new_thin(pool, origin_size, 0, :origin => cache_stack.cache) do |snap|
            fs = FS::file_system(:xfs, snap)
            fs.with_mount(MOUNT_DIR) do
              ProcessControl.run("dd if=/dev/zero of=#{MOUNT_DIR}/ddfile2 bs=1M count=100")
            end
          end
        end
      end
    end
  end
end


#----------------------------------------------------------------
