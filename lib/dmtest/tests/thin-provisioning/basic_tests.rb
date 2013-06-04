require 'config'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

class BasicTests < ThinpTestCase
  include Tags
  include Utils

  def setup
    super
  end

  tag :thinp_target

  def test_overwrite_a_linear_device
    linear_table = Table.new(LinearTarget.new(@volume_size, @data_dev, 0))
    with_dev(linear_table) {|linear_dev| dt_device(linear_dev)}
  end

  def test_ext4_weirdness
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        thin_fs = FS::file_system(:ext4, thin)
        thin_fs.format
        thin.pause {pool.message(0, "create_snap 1 0")}
        dt_device(thin)
      end
    end
  end

  tag :thinp_target, :slow

  def test_overwriting_various_thin_devices
    # we keep tearing down the pool and setting it back up so that we
    # can trigger a thin_repair check at each stage.

    info "dt an unprovisioned thin device"
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) {|thin| dt_device(thin)}
    end

    info "dt a fully provisioned thin device"
    with_standard_pool(@size) do |pool|
      with_thin(pool, @volume_size, 0) {|thin| dt_device(thin)}
    end

    info "dt a snapshot of a fully provisioned device"
    with_standard_pool(@size) do |pool|
      with_new_snap(pool, @volume_size, 1, 0) {|snap| dt_device(snap)}
    end

    info "dt a snapshot with no sharing"
    with_standard_pool(@size) do |pool|
      with_thin(pool, @volume_size, 1) {|snap| dt_device(snap)}
    end
  end

  def test_dd_benchmark
    with_standard_pool(@size) do |pool|

      info "wipe an unprovisioned thin device"
      with_new_thin(pool, @volume_size, 0) {|thin| wipe_device(thin)}

      info "wipe a fully provisioned thin device"
      with_thin(pool, @volume_size, 0) {|thin| wipe_device(thin)}

      info "wipe a snapshot of a fully provisioned device"
      with_new_snap(pool, @volume_size, 1, 0) {|snap| wipe_device(snap)}

      info "wipe a snapshot with no sharing"
      with_thin(pool, @volume_size, 1) {|snap| wipe_device(snap)}
    end
  end
end

#----------------------------------------------------------------
