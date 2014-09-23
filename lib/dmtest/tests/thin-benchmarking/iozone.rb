require 'dmtest/log'
require 'dmtest/disk-units'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

# Investigating bz 1145230
class IOZoneTests < ThinpTestCase
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
      ProcessControl.run("iozone -s 1g -t 2 -i 0 -i 2")
    end
  end

  #--------------------------------

  def test_iozone_thin
    wipe_device(@metadata_dev, 8)

    with_standard_pool(@size, :block_size => k(256)) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
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
