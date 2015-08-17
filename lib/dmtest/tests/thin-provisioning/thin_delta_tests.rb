require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'
require 'dmtest/xml_format'
require 'dmtest/pattern_stomper'
require 'dmtest/tests/thin-provisioning/metadata-generator'

#----------------------------------------------------------------

class ThinDeltaTests < ThinpTestCase
  include Utils
  include MetadataGenerator
  extend TestUtils

  # We prepare two thin devices that share some blocks.
  def prepare_md
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin1|
        stomper1 = PatternStomper.new(thin1.path, @data_block_size, :needs_zero => false)
        stomper1.stamp(50)

        with_new_snap(pool, @volume_size, 1, 0, thin1) do |thin2|
          stomper2 = stomper1.fork(thin2.path)
          stomper2.stamp(50)
        end

        stomper1.stamp(50)
      end
    end
  end

  define_test :delta do
    prepare_md

    ProcessControl.run("thin_delta --snap1 0 --snap2 1 #{@metadata_dev}")

    dump_metadata(@metadata_dev) do |xml_path|
    end
  end

  define_test :metadata_snap_with_live_pool do
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin1|
        stomper1 = PatternStomper.new(thin1.path, @data_block_size, :needs_zero => false)
        stomper1.stamp(50)

        with_new_snap(pool, @volume_size, 1, 0, thin1) do |thin2|
          stomper2 = stomper1.fork(thin2.path)
          stomper2.stamp(50)
        end

        stomper1.stamp(50)

        pool.message(0, "reserve_metadata_snap")
        ProcessControl.run("thin_delta --snap1 0 --snap2 1 -m #{@metadata_dev}")

        status = PoolStatus.new(pool)
        ProcessControl.run("thin_delta --snap1 0 --snap2 1 -m#{status.held_root} #{@metadata_dev}")
        pool.message(0, "release_metadata_snap")
      end
    end
  end
end

#----------------------------------------------------------------
