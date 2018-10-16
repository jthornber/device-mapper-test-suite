require 'dmtest/fs'
require 'dmtest/utils'
require 'dmtest/disk-units'
require 'dmtest/thinp-test'
require 'dmtest/snapshot_utils'
require 'dmtest/snapshot_stack'

#----------------------------------------------------------------

class ThroughputTests < ThinpTestCase
  include Utils
  include DiskUnits
  include SnapshotUtils
  extend TestUtils

  PERSISTENT = [:N, :P]
  FSTYPES = [:xfs, :ext4]

  def with_fs(dev, fs_type)
    puts "formatting ..."
    fs = FS::file_system(fs_type, dev)
    fs.format

    fs.with_mount('./bench_mnt') do
      Dir.chdir('./bench_mnt') do
        yield
      end
    end
  end

  def across_various_io_sizes(&block)
    [k(64), k(128), k(256), k(512), k(1024)].each do |io_size|
      block.call(io_size)
    end
  end

  def across_various_chunk_sizes(&block)
    [k(4), k(8), k(16), k(32), k(64)].each do |chunk_size|
      block.call(chunk_size)
    end
  end

  def across_various_chunk_and_io_sizes(&block)
    across_various_chunk_sizes do |chunk_size|
      across_various_io_sizes do |io_size|
        block.call(chunk_size, io_size)
      end
    end
  end

  def throughput_snapped(chunk_size, io_size, persistent)
    nr_chunks = div_up(@volume_size, chunk_size)
    origin_size = nr_chunks * chunk_size
    snapshot_size = max_snapshot_size(origin_size, chunk_size, persistent)

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => origin_size)
    s.activate do
      s.with_new_snap(0, snapshot_size, persistent, chunk_size) do
        report_time("volume size = #{origin_size}, chunk_size = #{chunk_size}, io_size = #{io_size}", STDERR) do
          ProcessControl.run("dd oflag=direct if=/dev/zero of=#{s.origin} bs=#{io_size * 512} count=#{dev_size(s.origin) / io_size}")
        end
      end
    end
  end

  def throughput_snap_broken(chunk_size, io_size, persistent)
    nr_chunks = div_up(@volume_size, chunk_size)
    origin_size = nr_chunks * chunk_size
    snapshot_size = max_snapshot_size(origin_size, chunk_size, persistent)

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => origin_size)
    s.activate do
      s.with_new_snap(0, snapshot_size, persistent, chunk_size) do
        wipe_device(s.origin)

        report_time("volume size = #{origin_size}, chunk_size = #{chunk_size}, io_size = #{io_size}", STDERR) do
          ProcessControl.run("dd oflag=direct if=/dev/zero of=#{s.origin} bs=#{io_size * 512} count=#{dev_size(s.origin) / io_size}")
        end
      end
    end
  end

  def throughput_linear(io_size)
    with_standard_linear(:data_size => @volume_size) do |linear|
      report_time("volume size = #{@volume_size}, io_size = #{io_size}", STDERR) do
        ProcessControl.run("dd oflag=direct if=/dev/zero of=#{linear} bs=#{io_size * 512} count=#{dev_size(linear) / io_size}")
      end
    end
  end

  def snap_breaking_throughput(persistent)
    across_various_chunk_and_io_sizes do |chunk_size, io_size|
      throughput_snapped(chunk_size, io_size, persistent)
    end
  end

  define_tests_across(:snap_breaking_throughput, PERSISTENT)

  def snap_already_broken_throughput(persistent)
    across_various_chunk_and_io_sizes do |chunk_size, io_size|
      throughput_snap_broken(chunk_size, io_size, persistent)
    end
  end

  define_tests_across(:snap_already_broken_throughput, PERSISTENT)

  define_test :linear_throughput do
    across_various_io_sizes do |io_size|
      throughput_linear(io_size)
    end
  end

  def multithreaded_layout_reread(device, io_size, desc)
    # Use iozone to layout interleaved files on device and then re-read with dd
    # using DIO
    report_time("iozone init #{desc}", STDERR) do
      ProcessControl.run("iozone -i 0 -i 1 -w -+n -+N -c -C -e -s 768m -r #{io_size / 2}k -t 8 -F ./1 ./2 ./3 ./4 ./5 ./6 ./7 ./8")
    end

    ProcessControl.run('echo 3 > /proc/sys/vm/drop_caches')

    report_time(" dd re-read #{desc}", STDERR) do
      ProcessControl.run("dd iflag=direct if=./1 of=/dev/null bs=#{io_size / 2}k")
    end
  end

  def throughput_multithreaded_layout_reread(fs_type, io_size, persistent)
    @volume_size = gig(7)

    with_standard_linear(:data_size => @volume_size) do |linear|
      with_fs(linear, fs_type) do
        multithreaded_layout_reread(linear, io_size,
                                    "linear, io_size = #{io_size}")
      end
    end

    across_various_chunk_sizes do |chunk_size|
      nr_chunks = div_up(@volume_size, chunk_size)
      origin_size = nr_chunks * chunk_size
      snapshot_size = max_snapshot_size(origin_size, chunk_size, persistent)

      s = SnapshotStack.new(@dm, @data_dev, :origin_size => origin_size)
      s.activate do
        with_fs(s.origin, fs_type) do
          s.with_new_snap(0, snapshot_size, persistent, chunk_size) do
            multithreaded_layout_reread(s.origin, io_size,
                                        "with snapshot chunk_size = #{chunk_size}, io_size = #{io_size}")
          end
        end
      end
    end
  end

  def multithreaded_layout_reread_throughput(fs_type, persistent)
    across_various_io_sizes do |io_size|
      throughput_multithreaded_layout_reread(fs_type, io_size, persistent)
    end
  end

  define_tests_across(:multithreaded_layout_reread_throughput, FSTYPES,
                      PERSISTENT)
end

#----------------------------------------------------------------
