require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'

#----------------------------------------------------------------

class ThroughputTests < ThinpTestCase
  include Tags
  include Utils
  include DiskUnits

  def setup
    super
  end

  tag :thinp_target

  #--------------------------------

  def throughput_unprovisioned(block_size, io_size)
    @blocks_per_dev = div_up(@volume_size, block_size)
    @volume_size = @blocks_per_dev * block_size

    # FIXME: add a :format option to with_standard_pool
    wipe_device(@metadata_dev, 8)

    with_standard_pool(@size, :zero => false, :block_size => block_size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        ProcessControl.run("dd if=/dev/zero of=#{thin} bs=#{io_size * 512} count=#{dev_size(thin) / io_size}")
      end
    end
  end

  def test_provisioning_throughput
    [k(64), k(128), k(256), k(512)].each do |block_size|
      [k(64), k(128), k(256), k(512)].each do |io_size|
        report_time("throughput time: block_size = #{block_size}, io_size = #{io_size}", STDERR) do
          throughput_unprovisioned(block_size, io_size)
        end
      end
    end
  end
end

#----------------------------------------------------------------
