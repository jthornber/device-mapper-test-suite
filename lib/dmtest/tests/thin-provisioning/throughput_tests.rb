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
    [k(64), k(128), k(256), k(512), k(1024)].each do |block_size|
      across_various_io_sizes do |io_size|
        block.call(block_size, io_size)
      end
    end
  end

  def across_various_bpa_and_io_sizes(&block)
    [1, 8, 16, 64, 256, 1024].each do |bpa|
      across_various_io_sizes do |io_size|
        block.call(bpa, io_size)
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

  #----------------------------------------------------------------

  extend DiskUnits
  VOLUME_SIZE = gig(1)

  def iozone_then_dd_read(device, io_size)
    count = (dev_size(device) / 9) / meg(1)


    # Use iozone to layout interleaved files on device and then re-read with dd using DIO
    fs = FS::file_system(:xfs, device)
    fs.format
    fs.with_mount("./mnt1") do
      report_time("iozone init, io_size = #{io_size}", STDERR) do
        ProcessControl.run("iozone -i 0 -i 1 -w -+n -+N -c -C -e -s #{count}m -r #{io_size / 2}k -t 8 -F ./mnt1/1 ./mnt1/2 ./mnt1/3 ./mnt1/4 ./mnt1/5 ./mnt1/6 ./mnt1/7 ./mnt1/8")
      end

      ProcessControl.run('echo 3 > /proc/sys/vm/drop_caches')

      report_time("dd re-read, io_size = #{io_size}", STDERR) do
        ProcessControl.run("dd iflag=direct if=./mnt1/1 of=/dev/null bs=#{io_size / 2}k")
        ProcessControl.run("dd iflag=direct if=./mnt1/2 of=/dev/null bs=#{io_size / 2}k")
        ProcessControl.run("dd iflag=direct if=./mnt1/3 of=/dev/null bs=#{io_size / 2}k")
        ProcessControl.run("dd iflag=direct if=./mnt1/4 of=/dev/null bs=#{io_size / 2}k")
      end
    end
  end

  def multi_write_single_read(device, io_size)
    report_time("dd write, io_size = #{io_size}", STDERR) do
      in_parallel(0, 1, 2, 3) do |thread|
        count = (dev_size(device) / 4) / io_size
        offset = count * thread
        ProcessControl.run("dd oflag=direct if=/dev/zero of=#{device} bs=#{io_size * 512} count=#{count} seek=#{offset}")
      end
    end

    # FIXME: shouldn't have an effect
    ProcessControl.run('echo 3 > /proc/sys/vm/drop_caches')

    report_time("dd read, io_size = #{io_size}", STDERR) do
      ProcessControl.run("dd iflag=direct if=#{device} of=/dev/null bs=#{io_size * 512}")
    end
  end

  def with_bpa_volume(block_size, bpa, desc, &block)
    @volume_size = VOLUME_SIZE

    @blocks_per_dev = div_up(@volume_size, block_size * bpa)
    @volume_size = @blocks_per_dev * block_size * bpa
    @size = @volume_size

    # FIXME: add a :format option to with_standard_pool
    wipe_device(@metadata_dev, 8)

    with_standard_pool(@size, :zero => false, :block_size => block_size,
                       :blocks_per_allocation => bpa) do |pool|
      with_new_thin(pool, @volume_size, 0, &block)

      pool.pause do
        dump_metadata(@metadata_dev) do |xml_path|
          file = "/tmp/metadata_#{desc}.xml"
          ProcessControl.run("cp #{xml_path} #{file}")
          STDERR.puts "metadata dumped to #{file}"
        end
      end
    end
  end

  def with_bpa_snap_volume(block_size, bpa, desc, &block)
    @volume_size = VOLUME_SIZE

    @blocks_per_dev = div_up(@volume_size, block_size * bpa)
    @volume_size = @blocks_per_dev * block_size * bpa
    @size = @volume_size * 2

    # FIXME: add a :format option to with_standard_pool
    wipe_device(@metadata_dev, 8)

    with_standard_pool(@size, :zero => false, :block_size => block_size,
                       :blocks_per_allocation => bpa) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)

        thin.pause do
          pool.message(0, "create_snap 1 0")
        end

        block.call(thin)
      end

      pool.pause do
        dump_metadata(@metadata_dev) do |xml_path|
          file = "/tmp/metadata_#{desc}.xml"
          ProcessControl.run("cp #{xml_path} #{file}")
          STDERR.puts "metadata dumped to #{file}"
        end
      end
    end
  end

  def test_multiple_writers_then_single_reader_linear
    across_various_io_sizes do |io_size|
      with_standard_linear(:data_size => VOLUME_SIZE) do |linear|
        multi_write_single_read(linear, io_size)
      end
    end
  end

  def test_multiple_writers_then_single_reader_thin_various_bpa
    block_size = k(64)
    across_various_bpa_and_io_sizes do |bpa, io_size|
      STDERR.puts "bpa = #{bpa}, io_size = #{io_size}"
      with_bpa_volume(block_size, bpa, "mw_sr_bpa_#{bpa}_io_size_#{io_size}") do |thin|
        multi_write_single_read(thin, io_size)
      end
    end
  end

  def test_multiple_writers_then_single_reader_thin_various_block_size
    across_various_block_and_io_sizes do |block_size, io_size|
      STDERR.puts "block_size = #{block_size}, io_size = #{io_size}"
      with_bpa_volume(block_size, 1, "mw_sr_block_#{block_size}_io_size_#{io_size}") do |thin|
        multi_write_single_read(thin, io_size)
      end
    end
  end

  def test_multiple_writers_then_single_reader_snap_various_bpa
    block_size = k(64)
    across_various_bpa_and_io_sizes do |bpa, io_size|
      STDERR.puts "bpa = #{bpa}, io_size = #{io_size}"
      with_bpa_snap_volume(block_size, bpa, "mw_sr_bpa_#{bpa}_io_size_#{io_size}") do |thin|
        multi_write_single_read(thin, io_size)
      end
    end
  end

  def test_iozone_writer_sequential_reader_linear
    across_various_io_sizes do |io_size|
      with_standard_linear(:data_size => VOLUME_SIZE) do |linear|
        iozone_then_dd_read(linear, io_size)
      end
    end
  end

  def test_iozone_writer_sequential_reader_thin_various_bpa
    block_size = k(64)
    across_various_bpa_and_io_sizes do |bpa, io_size|
      STDERR.puts "bpa = #{bpa}, io_size = #{io_size}"
      with_bpa_volume(block_size, bpa, "mw_sr_bpa_#{bpa}_io_size_#{io_size}") do |thin|
        iozone_then_dd_read(thin, io_size)
      end
    end
  end
end

#----------------------------------------------------------------
