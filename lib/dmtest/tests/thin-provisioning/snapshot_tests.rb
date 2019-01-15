require 'dmtest/dataset'
require 'dmtest/fs'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'

# these added for the dataset stuff
require 'fileutils'

#----------------------------------------------------------------

class SnapshotTests < ThinpTestCase
  include Utils
  include DiskUnits
  include GitExtract
  extend TestUtils

  def setup
    super
    @volume_size = @size / 4 if @volume_size.nil?
  end

  def do_create_snap(fs_type)
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        thin_fs = FS::file_system(fs_type, thin)
        thin_fs.format
        thin_fs.with_mount("./mnt1") do
          ds = Dataset.read(LP('compile-bench-datasets/dataset-unpatched'))
          Dir.chdir('mnt1') { ds.apply(1000) }

          with_new_snap(pool, @volume_size, 1, 0, thin) do |snap|
            snap_fs = FS::file_system(fs_type, snap)
            snap_fs.with_mount("./mnt2") do
              ds = Dataset.read(LP('compile-bench-datasets/dataset-unpatched-compiled'))
              Dir.chdir('mnt2') { ds.apply(1000) }
            end
          end
        end
      end
    end
  end

  def do_break_sharing(fs_type)
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        thin_fs = FS::file_system(fs_type, thin)
        thin_fs.format

	report_time("writing first dataset") do
          thin_fs.with_mount("./mnt1") do
            ds = Dataset.read(LP('compile-bench-datasets/dataset-unpatched'))
            Dir.chdir('mnt1') { ds.apply(1000) }
          end
        end
      end

      with_new_snap(pool, @volume_size, 1, 0) do |snap|
        snap_fs = FS::file_system(fs_type, snap)
	report_time("wrting second dataset") do
          snap_fs.with_mount("./mnt2") do
            ds = Dataset.read(LP('compile-bench-datasets/dataset-unpatched-compiled'))
            Dir.chdir('mnt2') { ds.apply(1000) }
          end
        end
      end
    end
  end

  def do_overwrite(fs_type)
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        thin_fs = FS::file_system(fs_type, thin)
	report_time("formatting") {thin_fs.format}

        ds = Dataset.read(LP('compile-bench-datasets/dataset-unpatched'))
	report_time("writing first dataset") do
          thin_fs.with_mount("./mnt1") do
            Dir.chdir('mnt1') { ds.apply(1000) }
          end
        end

	report_time("writing second dataset") do
        thin_fs.with_mount("./mnt1") do
            Dir.chdir('mnt1') { ds.apply(1000) }
          end
        end
      end
    end
  end

  tag :thinp_target

  define_test :thin_overwrite_ext4 do
    do_overwrite(:ext4)
  end

  define_test :thin_overwrite_xfs do
    do_overwrite(:xfs)
  end

  define_test :create_snap_ext4 do
    do_create_snap(:ext4)
  end

  define_test :create_snap_xfs do
    do_create_snap(:xfs)
  end

  define_test :break_sharing_ext4 do
    do_break_sharing(:ext4)
  end

  define_test :break_sharing_xfs do
    do_break_sharing(:xfs)
  end

  define_test :pool_utilization_block do
    thin_size = gig(1)

    # meg(63) would fail, since we'd need extra blocks for the
    # false-positive breaking of in flight blocks.  (Wipe_device()
    # writes in 64m blocks).
    extra = meg(64)

    with_standard_pool(thin_size * 2 + extra) do |pool|
      with_new_thin(pool, thin_size, 0) do |thin|
        wipe_device(thin)

        with_new_snap(pool, thin_size, 1, 0, thin) do |snap|
          wipe_device(thin)
          wipe_device(snap)
        end
      end
    end
  end

  define_test :many_snapshots_of_same_volume do
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        dt_device(thin)

        thin.pause do
          1.upto(1000) do |id|
            pool.message(0, "create_snap #{id} 0")
          end
        end

        dt_device(thin)
      end

      with_thin(pool, @volume_size, 1) do |thin|
        dt_device(thin)
      end
    end
  end

  tag :thinp_target, :slow

  define_test :parallel_io_to_shared_thins do
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)
      end

      1.upto(5) do |id|
        pool.message(0, "create_snap #{id} 0")
      end

      with_thins(pool, @volume_size, 0, 1, 2, 3, 4, 5) do |*thins|
        in_parallel(*thins) {|thin| dt_device(thin)}
      end
    end
  end

  # This test is specifically aimed at exercising the auxillery ref
  # count tree in the metadata.
  define_test :ref_count_tree do
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) {|thin| wipe_device(thin)}

      1.upto(5) do |id|
        pool.message(0, "create_snap #{id} 0")
      end

      with_thins(pool, @volume_size, 0, 1, 2, 3, 4, 5) do |*thins|
        thins.each do |thin|
          wipe_device(thin)
        end
      end
    end
  end

  # Break sharing by writing to a snapshot
  define_test :pattern_stomp_snap do
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        origin_stomper = PatternStomper.new(thin.path, @data_block_size, :needs_zero => false)
        origin_stomper.stamp(20)

        with_new_snap(pool, @volume_size, 1, 0, thin) do |snap|
          snap_stomper = origin_stomper.fork(snap.path)
          snap_stomper.verify(0, 1)

          snap_stomper.stamp(10)
          snap_stomper.verify(0, 2)

          origin_stomper.verify(0, 1)
        end
      end
    end
  end

  # Break sharing by writing to the origin
  define_test :pattern_stomp_origin do
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        origin_stomper = PatternStomper.new(thin.path, @data_block_size, :needs_zero => false)
        origin_stomper.stamp(20)

        with_new_snap(pool, @volume_size, 1, 0, thin) do |snap|
          snap_stomper = origin_stomper.fork(snap.path)
          
          origin_stomper.verify(0, 1)

          origin_stomper.stamp(10)
          origin_stomper.verify(0, 2)

          snap_stomper.verify(0, 1)
        end
      end
    end
  end

  define_test :many_snaps_with_changes do
    fs_type = :ext4

    with_standard_pool(gig(100)) do |pool|
      with_new_thin(pool, gig(20), 0) do |thin|
        git_prepare(thin, fs_type);

        TAGS.size.times do |n|
          thin.pause do
            pool.message(0, "create_snap #{n + 1} 0")
          end

          git_extract(thin, fs_type, TAGS[n..n])
        end
      end
    end
  end

  define_test :try_and_create_duplicates do
    fs_type = :ext4

    with_standard_pool(gig(100)) do |pool|
      with_new_thin(pool, gig(20), 0) do |thin|
        git_prepare(thin, fs_type);

        with_new_snap(pool, gig(20), 1, 0, thin) do |snap|
          git_extract(thin, fs_type, TAGS[10..10])
          git_extract(thin, fs_type, TAGS[0..2])

          git_extract(thin, fs_type, TAGS[20..20])
          git_extract(snap, fs_type, TAGS[0..2])
        end

      end
    end
  end
end

#----------------------------------------------------------------
