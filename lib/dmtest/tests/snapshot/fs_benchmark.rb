require 'dmtest/fs'
require 'dmtest/disk-units'
require 'dmtest/thinp-test'
require 'dmtest/snapshot_utils'
require 'dmtest/snapshot_stack'

#----------------------------------------------------------------

class FSBench < ThinpTestCase
  include DiskUnits
  include SnapshotUtils
  extend TestUtils

  PERSISTENT = [:P, :N]
  FSTYPES = [:xfs, :ext4]

  def setup
    super

    @chunk_size = k(4)
  end

  def timed_block(desc, &block)
    lambda {report_time(desc, &block)}
  end

  def bonnie(dir = '.')
    ProcessControl::run("bonnie++ -d #{dir} -r 0 -u root -s 2048")
  end

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

  def raw_test(fs_type, &block)
    with_fs(@data_dev, fs_type, &timed_block("raw test", &block))
  end

  def rolling_snap_test(fs_type, persistent, &block)
    origin_size = @size / 2
    snapshot_size = max_snapshot_size(origin_size, @chunk_size, persistent)

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => origin_size)
    s.activate do
      body = lambda {report_time("rolling snap", &block)}

      with_fs(s.origin, fs_type) do
        report_time("origin", &body)

        s.with_new_snap(0, snapshot_size, persistent, @chunk_size) do
          report_time("re-running with snap", &body)
          report_time("broken sharing", &body)
        end

        s.with_new_snap(0, snapshot_size, persistent, @chunk_size) do
          report_time("and again, with a different snap", &body)
          report_time("broken sharing", &body)
        end
      end
    end
  end

  def bonnie_raw_device(fs_type)
    raw_test(fs_type) {bonnie}
  end

  define_tests_across(:bonnie_raw_device, FSTYPES)

  def bonnie_rolling_snap(fs_type, persistent)
    rolling_snap_test(fs_type, persistent) {bonnie}
  end

  define_tests_across(:bonnie_rolling_snap, FSTYPES, PERSISTENT)
end

#----------------------------------------------------------------
