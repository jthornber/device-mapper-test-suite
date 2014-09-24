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

  def do_iozone(dev)
    with_fs(dev, :xfs) do
      report_time("Initial write and rewrite", STDERR) do
        ProcessControl.run("iozone -s 1g -t 8 -i 0 -C -w -c -e -+n -r 64k")
      end

      ProcessControl.run('echo 3 > /proc/sys/vm/drop_caches')

      report_time("Subsequent random io storm", STDERR) do
        ProcessControl.run("iozone -s 1g -t 8 -i 2 -C -w -c -e -+n -r 64k")
      end
    end
  end

  #--------------------------------

  def test_iozone_thin
    wipe_device(@metadata_dev, 8)

    size = dev_size(@data_dev)
    with_standard_pool(size, :zero => false, :block_size => meg(4)) do |pool|
      with_new_thin(pool, size, 0) do |thin|
        do_iozone(thin)
      end
    end
  end

  def test_iozone_linear
    with_standard_linear do |linear|
      do_iozone(linear)
    end
  end
end

#----------------------------------------------------------------
