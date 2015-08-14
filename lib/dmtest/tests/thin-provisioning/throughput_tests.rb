require 'dmtest/analysis'
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
  include XMLFormat
  extend TestUtils

  def setup
    super
  end

  tag :thinp_target

  def read_metadata
    dump_metadata(@metadata_dev) do |xml_path|
      File.open(xml_path, 'r') do |io|
        read_xml(io)            # this is the return value
      end
    end
  end

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

  define_test :provisioning_throughput do
    across_various_block_and_io_sizes do |block_size, io_size|
      throughput_unprovisioned(block_size, io_size)
    end
  end

  define_test :snap_breaking_throughput do
    across_various_block_and_io_sizes do |block_size, io_size|
      throughput_snapped(block_size, io_size)
    end      
  end

  define_test :snap_already_broken_throughput do
    across_various_block_and_io_sizes do |block_size, io_size|
      throughput_snap_broken(block_size, io_size)
    end
  end

  define_test :linear_throughput do
    across_various_io_sizes do |io_size|
      throughput_linear(io_size)
    end
  end

  def multithreaded_layout_reread(device, io_size, desc)
    # Use iozone to layout interleaved files on device and then re-read with dd using DIO
    fs = FS::file_system(:xfs, device)
    fs.format
    fs.with_mount("./mnt1") do
      report_time("iozone init #{desc}", STDERR) do
        ProcessControl.run("iozone -i 0 -i 1 -w -+n -+N -c -C -e -s 768m -r #{io_size / 2}k -t 8 -F ./mnt1/1 ./mnt1/2 ./mnt1/3 ./mnt1/4 ./mnt1/5 ./mnt1/6 ./mnt1/7 ./mnt1/8")
      end

      ProcessControl.run('echo 3 > /proc/sys/vm/drop_caches')

      report_time(" dd re-read #{desc}", STDERR) do
        ProcessControl.run("dd iflag=direct if=./mnt1/1 of=/dev/null bs=#{io_size / 2}k")
      end
    end
  end

  def throughput_multithreaded_layout_reread(block_size, io_size)
    # currently assumes underlying striped storage w/ chunk=64K stripe=256K
    @volume_size = gig(7)

    @blocks_per_dev = div_up(@volume_size, block_size)
    @volume_size = @blocks_per_dev * block_size
    @size = @volume_size

    with_standard_pool(@size, :zero => false, :block_size => block_size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        multithreaded_layout_reread(thin, io_size,
                                    "block_size = #{block_size}, io_size = #{io_size}")
      end
    end
  end

  def throughput_multithreaded_layout_reread_linear(block_size, io_size)
    with_standard_linear(:data_size => gig(7)) do |linear|
      multithreaded_layout_reread(linear, block_size, io_size)
    end
  end

  define_test :multithreaded_layout_reread_throughput do
    across_various_block_and_io_sizes do |block_size, io_size|
      throughput_multithreaded_layout_reread(block_size, io_size)
    end
  end

  #--------------------------------

  def prepare_multithreaded_layout(pool, block_size, io_size)
    with_new_thin(pool, @volume_size, 0) do |thin|
      # Use iozone to layout interleaved files on device and then re-read with dd using DIO
      fs = FS::file_system(:xfs, thin)
      fs.format
      fs.with_mount("./mnt1") do
        report_time("iozone init", STDERR) do
          ProcessControl.run("iozone -i 0 -i 1 -w -+n -+N -c -C -e -s 768m -r #{io_size / 2}k -t 8 -F ./mnt1/1 ./mnt1/2 ./mnt1/3 ./mnt1/4 ./mnt1/5 ./mnt1/6 ./mnt1/7 ./mnt1/8")
        end
      end
    end
  end

  define_test :multithreaded_layout_analysis do
    File.open("multithreaded_layout_analysis.log", "w") do |file|
      across_various_block_and_io_sizes do |block_size, io_size|
        file.puts "block_size = #{block_size}, io_size = #{io_size}"

        # currently assumes underlying striped storage w/ chunk=64K stripe=256K
        @volume_size = gig(7)

        @blocks_per_dev = div_up(@volume_size, block_size)
        @volume_size = @blocks_per_dev * block_size
        @size = @volume_size

        with_standard_pool(@size, :zero => false, :block_size => block_size) do |pool|
          prepare_multithreaded_layout(pool, block_size, io_size)
        end

        a = MetadataAnalysis.new(read_metadata())
        a.fragmentations(file)
        file.flush
      end
    end
  end
end

#----------------------------------------------------------------
