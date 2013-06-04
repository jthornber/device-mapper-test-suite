require 'config'
require 'dmtest/dataset'
require 'dmtest/fs'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'

# these added for the dataset stuff
require 'fileutils'

#----------------------------------------------------------------

class SnapshotTests < ThinpTestCase
  include Tags
  include Utils

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
          ds = Dataset.read('compile-bench-datasets/dataset-unpatched')
          Dir.chdir('mnt1') { ds.apply(1000) }

          with_new_snap(pool, @volume_size, 1, 0, thin) do |snap|
            snap_fs = FS::file_system(fs_type, snap)
            snap_fs.with_mount("./mnt2") do
              ds = Dataset.read('compile-bench-datasets/dataset-unpatched-compiled')
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
            ds = Dataset.read('compile-bench-datasets/dataset-unpatched')
            Dir.chdir('mnt1') { ds.apply(1000) }
          end
        end
      end

      with_new_snap(pool, @volume_size, 1, 0) do |snap|
        snap_fs = FS::file_system(fs_type, snap)
	report_time("wrting second dataset") do
          snap_fs.with_mount("./mnt2") do
            ds = Dataset.read('compile-bench-datasets/dataset-unpatched-compiled')
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

        ds = Dataset.read('compile-bench-datasets/dataset-unpatched')
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

  def test_thin_overwrite_ext4
    do_overwrite(:ext4)
  end

  def test_thin_overwrite_xfs
    do_overwrite(:xfs)
  end

  def test_create_snap_ext4
    do_create_snap(:ext4)
  end

  def test_create_snap_xfs
    do_create_snap(:xfs)
  end

  def test_break_sharing_ext4
    do_break_sharing(:ext4)
  end

  def test_break_sharing_xfs
    do_break_sharing(:xfs)
  end

  def test_many_snapshots_of_same_volume
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

  def test_parallel_io_to_shared_thins
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
  def test_ref_count_tree
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
end

#----------------------------------------------------------------
