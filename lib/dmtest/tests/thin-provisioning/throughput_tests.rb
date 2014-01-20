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

  def across_various_bpa_block_and_io_sizes(&block)
    [1, 10, 20].each do |blocks_per_allocation|
      across_various_block_and_io_sizes do |block_size, io_size|
        block.call(block_size, io_size, blocks_per_allocation)
      end
      STDERR.puts "\n"
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

  def multithreaded_layout_reread(device, block_size, io_size, bpa)
    # Use iozone to layout interleaved files on device and then re-read with dd using DIO
    fs = FS::file_system(:xfs, device)
    fs.format
    fs.with_mount("./mnt1") do

      report_time("iozone init block_size = #{block_size}, io_size = #{io_size}, blocks_per_allocation = #{bpa}", STDERR) do
        ProcessControl.run("iozone -i 0 -i 1 -w -+n -+N -c -C -e -s 768m -r #{io_size / 2}k -t 8 -F ./mnt1/1 ./mnt1/2 ./mnt1/3 ./mnt1/4 ./mnt1/5 ./mnt1/6 ./mnt1/7 ./mnt1/8")
      end

      ProcessControl.run('echo 3 > /proc/sys/vm/drop_caches')

      report_time(" dd re-read  block_size = #{block_size}, io_size = #{io_size}, blocks_per_allocation = #{bpa}", STDERR) do
        ProcessControl.run("dd iflag=direct if=./mnt1/1 of=/dev/null bs=#{io_size / 2}k")
      end
    end
  end

  def multithreaded_layout_read(device, block_size, io_size, bpa)
    report_time("dd write  block_size = #{block_size}, io_size = #{io_size}, blocks_per_allocation = #{bpa}", STDERR) do
      in_parallel(0, 1, 2, 3) {|offset| ProcessControl.run("dd oflag=direct if=/dev/zero of=#{device} bs=#{io_size * 512} count=#{gig(1) / io_size} seek=#{offset * (gig(1) / io_size)}")}
    end

    report_time(" dd read  block_size = #{block_size}, io_size = #{io_size}, blocks_per_allocation = #{bpa}", STDERR) do
      ProcessControl.run("dd iflag=direct if=#{device} of=/dev/null bs=#{io_size * 512} count=#{gig(1) / io_size}")
    end
  end

  def throughput_multithreaded_layout_io(block_size, io_size, bpa, desc, &block)
    @volume_size = gig(7)

    @blocks_per_dev = div_up(@volume_size, block_size * bpa)
    @volume_size = @blocks_per_dev * block_size * bpa
    @size = @volume_size

    # FIXME: add a :format option to with_standard_pool
    wipe_device(@metadata_dev, 8)

    with_standard_pool(@size, :zero => false, :block_size => block_size,
                       :blocks_per_allocation => bpa) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        block.call(thin, block_size, io_size, bpa)
      end

      pool.suspend
      dump_metadata(@metadata_dev) do |xml_path|
        # FIXME: log to unique location
        ProcessControl.run("cat #{xml_path} > /tmp/testest/#{desc}_bs#{block_size}_io#{io_size}_bpa#{bpa}.txt")
      end
      pool.resume
    end
  end

  def throughput_multithreaded_layout_io_linear(block_size, io_size, &block)
    with_standard_linear(:data_size => gig(7)) do |linear|
      block.call(linear, block_size, io_size, 1)
    end
  end

  def harness_multithreaded_layout_io_throughput(&block)
    # compare: linear vs blocks_per_allocation=1
    STDERR.puts "\nlinear:"
    across_various_block_and_io_sizes do |block_size, io_size|
      throughput_multithreaded_layout_io_linear(block_size, io_size, &block)
    end

    # then compare: use of blocks_per_allocation=10
    STDERR.puts "\nthin w/ varied blocks_per_allocation:"
    across_various_bpa_block_and_io_sizes do |block_size, io_size, bpa|
      throughput_multithreaded_layout_io(block_size, io_size, bpa, "thin_varied_bpa", &block)
    end

    # versus: native large blocksizes
    STDERR.puts "\nthin w/ native large blocksizes:"
    [k(640), k(1280), k(2560), k(5120), k(10240)].each do |block_size|
      across_various_io_sizes do |io_size|
        throughput_multithreaded_layout_io(block_size, io_size, 1, "thin_large_bs", &block)
      end
    end
  end

  def test_multithreaded_layout_reread_throughput
    harness_multithreaded_layout_io_throughput do |device, block_size, io_size, bpa|
      multithreaded_layout_reread(device, block_size, io_size, bpa)
    end
  end

  def test_multithreaded_layout_read_throughput
    harness_multithreaded_layout_io_throughput do |device, block_size, io_size, bpa|
      multithreaded_layout_read(device, block_size, io_size, bpa)
    end
  end

end

#----------------------------------------------------------------
