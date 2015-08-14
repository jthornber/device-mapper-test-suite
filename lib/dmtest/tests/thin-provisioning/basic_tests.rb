require 'dmtest/blktrace'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/test-utils'

#----------------------------------------------------------------

class BasicTests < ThinpTestCase
  include Tags
  include Utils
  include BlkTrace
  extend TestUtils

  def setup
    super
  end

  tag :thinp_target

  define_test :test_overwrite_a_linear_device do
    linear_table = Table.new(LinearTarget.new(@volume_size, @data_dev, 0))
    with_dev(linear_table) {|linear_dev| dt_device(linear_dev)}
  end

  define_test :ext4_weirdness do
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

  define_test :overwriting_various_thin_devices do
    # we keep tearing down the pool and setting it back up so that we
    # can trigger a thin_repair check at each stage.

    info "dt an unprovisioned thin device"
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) {|thin| dt_device(thin)}
    end

    info "dt a fully provisioned thin device"
    with_standard_pool(@size, :format => false) do |pool|
      with_thin(pool, @volume_size, 0) {|thin| dt_device(thin)}
    end

    info "dt a snapshot of a fully provisioned device"
    with_standard_pool(@size, :format => false) do |pool|
      with_new_snap(pool, @volume_size, 1, 0) {|snap| dt_device(snap)}
    end

    info "dt a snapshot with no sharing"
    with_standard_pool(@size, :format => false) do |pool|
      with_thin(pool, @volume_size, 1) {|snap| dt_device(snap)}
    end
  end

  define_test :dd_benchmark do
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

  define_test :pool_without_thin_devices_does_not_commit do
    with_standard_pool(@size) do |pool|
      traces, _ = blktrace(@metadata_dev) do
        sleep 10
      end
      STDERR.puts traces[0]
      assert(traces[0].empty?)
    end
  end
end

#----------------------------------------------------------------
