require 'dmtest/log'
require 'dmtest/disk-units'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

class MetadataLoadingTests < ThinpTestCase
  include Tags
  include Utils
  include DiskUnits

  def setup
    super
  end

  tag :thinp_target, :slow

  def test_benchmark_io_across_a_totally_provisioned_device
    volume_size = [@volume_size * 5, @size].min

    with_standard_pool(@size) do |pool|
      with_new_thin(pool, volume_size, 0) do |thin|
        report_time("dd to provision", STDERR) do
          wipe_device(thin)
        end
      end
    end

    # now we reload it and time a dt across it
    with_standard_pool(@size) do |pool|
      with_thin(pool, volume_size, 0) do |thin|
        apply_load(thin, 'metadata not in memory')
        apply_load(thin, 'metadata in memory')
      end
    end
  end

  private
  def apply_load(dev, metadata_state)
    report_time("dd across provisioned thin, #{metadata_state}", STDERR) do
      wipe_device(dev)
    end
  end
end

#----------------------------------------------------------------
