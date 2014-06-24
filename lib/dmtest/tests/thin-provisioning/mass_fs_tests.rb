require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/status'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/tvm'

#----------------------------------------------------------------

class MassFsTests < ThinpTestCase
  include Tags
  include TinyVolumeManager
  include Utils

  def setup
    super

    @max = @mass_fs_tests_parallel_runs
  end

  # (format, fsck, mount, copy|)dt (, umount, fsck)
  def load_cycle(dev, fs_type, io_type, mount_point)
    if (fs_type == :device)
      dt_device(dev, io_type, "iot", dev_size(dev))
    else
      fs = FS::file_system(fs_type, dev)
      report_time('formatting') {fs.format}
      report_time('fsck') {fs.check}
      report_time('mount + rsync + umount') do
        fs.with_mount(mount_point) do
          if (io_type == "rsync")
            report_time('rsync') do
              ProcessControl.run("rsync -lr /usr/bin #{mount_point} > /dev/null; sync")
            end
          else
            report_time("dt #{io_type}") do
              dt_device("#{mount_point}/#{dev.name}", io_type, "iot", dev_size(dev) / 10 * 8)
            end
          end
        end
      end

      report_time('fsck after rsync+umount') {fs.check}
    end
  end

  #
  # bulk configuration followed by load
  #
  def _mass_linear_create_apply_remove(fs_type, io_type, max)
    tvm = VM.new
    tvm.add_allocation_volume(@data_dev)

    size = tvm.free_space / max
    size = @volume_size if size > @volume_size
    names = Array.new
    1.upto(max) do |i|
      name = "linear-#{i}"
      tvm.add_volume(linear_vol(name, size))
      names << name
    end

    with_devs(*(names.map {|n| tvm.table(n)})) do |*devs|
      in_parallel(*devs) {|dev| load_cycle(dev, fs_type, io_type, "mnt_#{dev.name}")}
    end
  end

  def _mass_create_apply_remove(fs_type, io_type, max)
    ids = (1..max).entries
    size = round_down(dev_size(@data_dev) / max, @data_block_size)
    size = @volume_size if size > @volume_size

    with_standard_pool(@size, :zero => false) do |pool|
      with_new_thins(pool, size, *ids) do |*thins|
        in_parallel(*thins) {|thin| load_cycle(thin, fs_type, io_type, "mnt_#{thin.name}") }
      end

      ids.each { |id| pool.message(0, "delete #{id}") }
      assert_equal(0, PoolStatus.new(pool).used_data_blocks)
    end
  end


  tag :linear_target, :slow

  def test_mass_linear_create_apply_remove_device
    _mass_linear_create_apply_remove(:device, "rsync", @max)
  end

  def test_mass_linear_create_apply_remove_ext4
    _mass_linear_create_apply_remove(:ext4, "rsync", @max)
  end

  def test_mass_linear_create_apply_remove_xfs
    _mass_linear_create_apply_remove(:xfs, "rsync", @max)
  end


  tag :thin_target, :slow, :bulk

  def test_mass_create_apply_remove_rsync_ext4
    _mass_create_apply_remove(:ext4, "rsync", @max)
  end

  def test_mass_create_apply_remove_rsync_xfs
    _mass_create_apply_remove(:xfs, "rsync", @max)
  end

  def test_mass_create_apply_remove_dtseq_ext4
    _mass_create_apply_remove(:ext4, "sequential", @max)
  end

  def test_mass_create_apply_remove_dtseq_xfs
    _mass_create_apply_remove(:xfs, "sequential", @max)
  end

  def test_mass_create_apply_remove_dtrandom_ext4
    _mass_create_apply_remove(:ext4, "random", @max)
  end

  def test_mass_create_apply_remove_dtrandom_xfs
    _mass_create_apply_remove(:xfs, "random", @max)
  end

  def test_mass_create_apply_remove_dtseq_device
    _mass_create_apply_remove(:device, "sequential", @max)
  end

  def test_mass_create_apply_remove_dtrandom_device
    _mass_create_apply_remove(:device, "random", @max)
  end

  #
  # configuration changes under load
  #
  def _config_load_one(pool, id, fs_type, io_type)
    pool.message(0, "create_thin #{id}")
    with_thin(pool, @volume_size, id) { |thin| load_cycle(thin, fs_type, io_type, "mnt_#{thin.name}") }
    pool.message(0, "delete #{id}")
  end

  def _mass_create_apply_remove_with_config_load(fs_type, io_type, max = nil)
    max = 128 if max.nil?
    ids = (1..max).entries
    sz = @size / max
    @volume_size = sz if @volume_size > sz

    with_standard_pool(@size, :zero => false) do |pool|
      in_parallel(*ids) {|id| _config_load_one(pool, id, fs_type, io_type)}
      assert_equal(0, PoolStatus.new(pool).used_data_blocks)
    end
  end

  tag :thin_target, :slow, :config_load

  def test_mass_create_apply_remove_with_config_load_rsync_ext4
    _mass_create_apply_remove_with_config_load(:ext4, "rsync" , @max)
  end

  def test_mass_create_apply_remove_with_config_load_rsync_xfs
    _mass_create_apply_remove_with_config_load(:xfs, "rsync" , @max)
  end

  def test_mass_create_apply_remove_with_config_load_dtseq_ext4
    _mass_create_apply_remove_with_config_load(:ext4, "sequential" , @max)
  end

  def test_mass_create_apply_remove_with_config_load_dtrandom_ext4
    _mass_create_apply_remove_with_config_load(:ext4, "random" , @max)
  end

  def test_mass_create_apply_remove_with_config_load_dtseq_xfs
    _mass_create_apply_remove_with_config_load(:xfs, "sequential", @max)
  end

  def test_mass_create_apply_remove_with_config_load_dtrandom_xfs
    _mass_create_apply_remove_with_config_load(:xfs, "random", @max)
  end

  def test_mass_create_apply_remove_with_config_load_dtseq_device
    _mass_create_apply_remove_with_config_load(:device, "sequential", @max)
  end

  def test_mass_create_apply_remove_with_config_load_dtrandom_device
    _mass_create_apply_remove_with_config_load(:device, "random", @max)
  end
end

#----------------------------------------------------------------
