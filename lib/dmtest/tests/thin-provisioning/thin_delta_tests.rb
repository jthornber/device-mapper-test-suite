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

  #--------------------------------

  def check_metadata(md, txt)
    metadata = nil
    expected = StringIO.new(txt)

    Utils::with_temp_file('metadata_xml') do |file|
      ProcessControl::run("thin_dump #{md} > #{file.path}")
      file.rewind
      assert FileUtils.compare_stream(file, expected)
    end
  end

  def check_delta(md, thin1, thin2, txt)
    metadata = nil
    expected = StringIO.new(txt)

    Utils::with_temp_file('metadata_xml') do |file|
      ProcessControl::run("thin_delta --snap1 #{thin1} --snap2 #{thin2} #{md} > #{file.path}")
      file.rewind
      assert FileUtils.compare_stream(file, expected)
    end
  end

  DUMP1 =<<EOF
<superblock uuid="" time="0" transaction="0" data_block_size="128" nr_data_blocks="163840">
  <device dev_id="0" mapped_blocks="1600" transaction="0" creation_time="0" snap_time="0">
    <range_mapping origin_begin="0" data_begin="0" length="1600" time="0"/>
  </device>
</superblock>
EOF

  DUMP2 =<<EOF
<superblock uuid="" time="1" transaction="0" data_block_size="128" nr_data_blocks="163840">
  <device dev_id="0" mapped_blocks="1600" transaction="0" creation_time="0" snap_time="1">
    <range_mapping origin_begin="0" data_begin="0" length="1600" time="0"/>
  </device>
  <device dev_id="1" mapped_blocks="1600" transaction="0" creation_time="1" snap_time="1">
    <single_mapping origin_block="0" data_block="0" time="0"/>
    <single_mapping origin_block="1" data_block="1600" time="1"/>
    <range_mapping origin_begin="2" data_begin="2" length="1598" time="0"/>
  </device>
</superblock>
EOF

  DELTA =<<EOF
<superblock uuid="" time="1" transaction="0" data_block_size="128" nr_data_blocks="163840">
  <diff left="0" right="1">
    <same begin="0" length="1"/>
    <different begin="1" length="1"/>
    <same begin="2" length="1598"/>
  </diff>
</superblock>
EOF

  # https://github.com/jthornber/thin-provisioning-tools/issues/39
  define_test :snap_with_single_block_difference do
    thin_size = meg(100)

    # Provision a thin
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, thin_size, 0) do |thin|
        wipe_device(thin)
      end
    end

    check_metadata(@metadata_dev, DUMP1)

    # Create a snap and break sharing in a single block
    with_standard_pool(@size, :format => false) do |pool|
      with_thin(pool, thin_size, 0) do |thin|
        with_new_snap(pool, thin_size, 1, 0) do |snap|
          ProcessControl::run("dd if=/dev/zero of=#{snap.path} bs=64K count=1 seek=1")
        end
      end
    end

    check_metadata(@metadata_dev, DUMP2)

    # Run thin delta
    check_delta(@metadata_dev, 0, 1, DELTA)
  end
end

#----------------------------------------------------------------
