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

  def across_various_io_sizes(&block)
    [k(64), k(128), k(256), k(512)].each do |io_size|
      block.call(io_size)
    end
  end

  def across_various_block_and_io_sizes(&block)
    [k(64), k(128), k(256), k(512)].each do |block_size|
      across_various_io_sizes do |io_size|
        block.call(block_size, io_size)
      end
    end
  end

  def throughput_unprovisioned(block_size, io_size)
    @blocks_per_dev = div_up(@volume_size, block_size)
    @volume_size = @blocks_per_dev * block_size

    # FIXME: add a :format option to with_standard_pool
    wipe_device(@metadata_dev, 8)

    with_standard_pool(@size, :zero => false, :block_size => block_size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        report_time("volume size = 1G, block_size = #{block_size}, io_size = #{io_size}", STDERR) do
          ProcessControl.run("dd oflag=direct if=/dev/zero of=#{thin} bs=#{io_size * 512} count=#{dev_size(thin) / io_size}")
        end
      end
    end
  end

  def throughput_snapped(block_size, io_size)
    @blocks_per_dev = div_up(@volume_size, block_size)
    @volume_size = @blocks_per_dev * block_size

    # FIXME: add a :format option to with_standard_pool
    wipe_device(@metadata_dev, 8)

    with_standard_pool(@size, :zero => false, :block_size => block_size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)

        thin.pause do
          pool.message(0, "create_snap 1 0")
        end

        report_time("volume size = 1G, block_size = #{block_size}, io_size = #{io_size}", STDERR) do
          ProcessControl.run("dd oflag=direct if=/dev/zero of=#{thin} bs=#{io_size * 512} count=#{dev_size(thin) / io_size}")
        end
      end
    end
  end

  def throughput_snap_broken(block_size, io_size)
    @blocks_per_dev = div_up(@volume_size, block_size)
    @volume_size = @blocks_per_dev * block_size

    # FIXME: add a :format option to with_standard_pool
    wipe_device(@metadata_dev, 8)

    with_standard_pool(@size, :zero => false, :block_size => block_size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)

        thin.pause do
          pool.message(0, "create_snap 1 0")
        end

        wipe_device(thin)

        report_time("volume size = 1G, block_size = #{block_size}, io_size = #{io_size}", STDERR) do
          ProcessControl.run("dd oflag=direct if=/dev/zero of=#{thin} bs=#{io_size * 512} count=#{dev_size(thin) / io_size}")
        end
      end
    end
  end

  def throughput_linear(io_size)
    with_standard_linear(:data_size => gig(1)) do |linear|
      report_time("volume size = 1G, io_size = #{io_size}", STDERR) do
        ProcessControl.run("dd oflag=direct if=/dev/zero of=#{linear} bs=#{io_size * 512} count=#{dev_size(linear) / io_size}")
      end
    end
  end

  def test_provisioning_throughput
    across_various_block_and_io_sizes do |block_size, io_size|
      throughput_unprovisioned(block_size, io_size)
    end
  end

  def test_snap_breaking_throughput
    across_various_block_and_io_sizes do |block_size, io_size|
      throughput_snapped(block_size, io_size)
    end      
  end

  def test_snap_already_broken_throughput
    across_various_block_and_io_sizes do |block_size, io_size|
      throughput_snap_broken(block_size, io_size)
    end
  end

  def test_linear_throughput
    across_various_io_sizes do |io_size|
      throughput_linear(io_size)
    end
  end
end

#----------------------------------------------------------------
