require 'dmtest/log'
require 'dmtest/disk-units'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

class ProvisioningTests < ThinpTestCase
  include Tags
  include Utils
  include DiskUnits

  def setup
    super
  end

  tag :thinp_target, :slow

  def test_wipe_with_various_block_sizes
    [k(64), k(128), k(192), k(512), k(1024)].each do |block_size|
      wipe_device(@metadata_dev, 8)

      with_standard_pool(@size, :block_size => block_size) do |pool|
        report_time("wipe thin device (block_size = #{block_size})", STDERR) do
          with_new_thin(pool, @volume_size, 0) do |thin|
            wipe_device(thin)
          end
        end
      end
    end
  end
end

#----------------------------------------------------------------
