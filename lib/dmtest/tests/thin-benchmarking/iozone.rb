require 'dmtest/blktrace'
require 'dmtest/log'
require 'dmtest/disk-units'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'

require 'pp'

#----------------------------------------------------------------

# Investigating bz 1145230
class IOZoneTests < ThinpTestCase
  include BlkTrace
  include Tags
  include Utils
  include DiskUnits

  def setup
    super
  end

  tag :thinp_target, :slow

  def with_fs(dev, fs_type, opts = {})
    puts "formatting ..."
    fs = FS::file_system(fs_type, dev)

    if opts.fetch(:format, true)
      fs.format
    end

    fs.with_mount('./bench_mnt') do
      Dir.chdir('./bench_mnt') do
        yield
      end
    end
  end

  def create_file_names(count)
    files = (1..count).map do |n| 
      "f%02d-8GB.ioz" % n
    end
  end

  def allocate_files(nr, nr_gig)
    files = create_file_names(nr)

    size = 1024 * 1024 * 1024 * nr_gig
    files.each do |f|
      `fallocate -l #{size} #{f}`
    end

    files
  end

  def drop_caches()
    ProcessControl.run('echo 3 > /proc/sys/vm/drop_caches')
  end

  def iozone_sequential_io(dev, nr_threads, nr_gig, files)
    report_time("sequential write", STDERR) do
      `iozone -s #{nr_gig}g -t #{nr_threads} -i 0 -C -w -c -e -+n -r 64k -F #{files.join(' ')}`
    end
  end

  def iozone_random_io(dev, nr_threads, nr_gig, files)
    report_time("Random io (read then write)", STDERR) do
      `iozone -s #{nr_gig}g -t #{nr_threads} -i 2 -C -w -c -e -+n -r 64k -F #{files.join(' ')}`
    end
  end

  def sequential_random(dev, nr_threads, nr_gig)
    with_fs(dev, :xfs) do
      files = allocate_files(nr_threads, nr_gig)
      drop_caches
      iozone_sequential_io(dev, nr_threads, nr_gig, files)
      drop_caches
      iozone_random_io(dev, nr_threads, nr_gig, files)
    end
  end

  def random_random(dev, nr_threads, nr_gig)
    with_fs(dev, :xfs) do
      files = allocate_files(nr_threads, nr_gig)
      drop_caches
      iozone_random_io(dev, nr_threads, nr_gig, files)
      drop_caches
      iozone_random_io(dev, nr_threads, nr_gig, files)
    end
  end

  def random_sequential(dev, nr_threads, nr_gig)
    with_fs(dev, :xfs) do
      files = allocate_files(nr_threads, nr_gig)
      drop_caches
      iozone_random_io(dev, nr_threads, nr_gig, files)
      drop_caches
      iozone_sequential_io(dev, nr_threads, nr_gig, files)
    end
  end

  #--------------------------------

  NR_THREADS = 4
  NR_GIG = 1

  def test_iozone_thin
    size = dev_size(@data_dev)
    with_standard_pool(size, :format => true, :zero => false, :block_size => k(256)) do |pool|
      with_new_thin(pool, size, 0) do |thin|
        random_random(thin, NR_THREADS, NR_GIG)
      end
    end
  end

  def test_iozone_snap
    size = dev_size(@data_dev)
    thin_size = dev_size(@data_dev) / 2
    with_standard_pool(size, :format => true, :zero => false, :block_size => k(256)) do |pool|
      with_new_thin(pool, thin_size, 0) do |thin|
        report_time("initial wipe", STDERR) do
          wipe_device(thin);
        end

        with_new_snap(pool, thin_size, 1, 0, thin) do |snap|
          random_random(thin, NR_THREADS, NR_GIG)
        end
      end
    end
  end

  def test_iozone_linear
    with_standard_linear do |linear|
      work_load2(linear, NR_THREADS, NR_GIG)
    end
  end

  def test_iozone_raw
    sequential_random(@data_dev, NR_THREADS, NR_GIG)
  end
end

#----------------------------------------------------------------
