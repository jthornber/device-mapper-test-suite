require 'dmtest/fs'
require 'dmtest/git'
require 'dmtest/utils'
require 'dmtest/dataset'
require 'dmtest/disk-units'
require 'dmtest/thinp-test'
require 'dmtest/snapshot_utils'
require 'dmtest/snapshot_stack'

#----------------------------------------------------------------

class BasicTests < ThinpTestCase
  include Utils
  include DiskUnits
  include GitExtract
  include SnapshotUtils
  extend TestUtils

  PERSISTENT = [:P, :N]
  FSTYPES = [:ext4, :xfs]

  def setup
    super

    @max = 16
    @chunk_size = k(4)
  end

  def do_create_snap(fs_type, persistent)
    snapshot_size = max_snapshot_size(@volume_size, @chunk_size, persistent)

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => @volume_size)
    s.activate do
      origin_fs = FS::file_system(fs_type, s.origin)
      origin_fs.format
      origin_fs.with_mount("./mnt1") do
        ds = Dataset.read(LP('compile-bench-datasets/dataset-unpatched'))
        Dir.chdir('mnt1') { ds.apply(1000) }

        s.with_new_snap(0, snapshot_size, persistent, @chunk_size) do |snap|
          snap_fs = FS::file_system(fs_type, snap)
          snap_fs.with_mount("./mnt2") do
            ds = Dataset.read(LP('compile-bench-datasets/dataset-unpatched-compiled'))
            Dir.chdir('mnt2') { ds.apply(1000) }
          end
        end
      end
    end
  end

  def create_snap(fs_type, persistent)
    do_create_snap(fs_type, persistent)
  end

  define_tests_across(:create_snap, FSTYPES, PERSISTENT)

  def many_snaps_with_changes(persistent)
    fs_type = :ext4
    origin_size = gig(5)
    snapshot_size = gig(1)
    ids = []

    cleanup = lambda {|s| ids.each {|id| s.drop_snap(id)}}

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => origin_size)
    s.activate do
      git_prepare(s.origin, fs_type);

      bracket(s, cleanup) do
        TAGS.size.times do |n|
          s.take_snap(n, snapshot_size, persistent, @chunk_size)
          ids << n

          git_extract(s.origin, fs_type, TAGS[n..n])
        end
      end
    end
  end

  define_tests_across(:many_snaps_with_changes, PERSISTENT)

  def parallel_io_to_many_snaps(persistent)
    snapshot_size = max_snapshot_size(@volume_size, @chunk_size, persistent)

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => @volume_size)
    s.activate do
      s.with_new_snaps(snapshot_size, persistent, @chunk_size, *(1..@max)) do |*snaps|
        in_parallel(s.origin, *snaps) do |dev|
          dt_device(dev, "random", "iot", @volume_size)
        end
      end
    end
  end

  define_tests_across(:parallel_io_to_many_snaps, PERSISTENT)

  def many_snapshots_of_same_volume(persistent)
    snapshot_size = max_snapshot_size(@volume_size, @chunk_size, persistent)

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => @volume_size)
    s.activate do
      dt_device(s.origin)
      s.with_new_snaps(snapshot_size, persistent, @chunk_size, *(1..@max)) do |snap1, *snaps|
        dt_device(s.origin)
        dt_device(snap1)
      end
    end
  end

  define_tests_across(:many_snapshots_of_same_volume, PERSISTENT)
end

#----------------------------------------------------------------
