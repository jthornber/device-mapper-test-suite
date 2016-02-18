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

  def check_command(cmd, txt)
    metadata = nil
    expected = StringIO.new(txt)

    Utils::with_temp_file('check_tmp') do |file|
      ProcessControl::run("#{cmd} > #{file.path}")
      file.rewind
      assert FileUtils.compare_stream(file, expected)
    end
  end

  def check_delta(md, thin1, thin2, txt)
    check_command("thin_delta --snap1 #{thin1} --snap2 #{thin2} #{md}", txt)
  end

  DDRange = Struct.new(:begin_m, :end_m)

  def run_dd(dev, r)
    ProcessControl::run("dd if=/dev/zero of=#{dev} bs=1M seek=#{r.begin_m} count=#{r.end_m - r.begin_m}")
  end

  def delta_test(range1, range2, delta)
    thin_size = meg(100)

    # Provision a thin
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, thin_size, 0) do |thin|
        run_dd(thin, range1)
      end

      with_new_snap(pool, thin_size, 1, 0) do |snap|
        run_dd(snap, range2)
      end
    end

    check_delta(@metadata_dev, 0, 1, delta)
  end

  #--------------------------------

  DELTA1 =<<EOF
<superblock uuid="" time="1" transaction="0" data_block_size="128" nr_data_blocks="163840">
  <diff left="0" right="1">
    <same begin="0" length="16"/>
    <different begin="16" length="16"/>
    <same begin="32" length="1568"/>
  </diff>
</superblock>
EOF

  # https://github.com/jthornber/thin-provisioning-tools/issues/39
  define_test :snap_with_single_block_difference1 do
    delta_test(DDRange.new(0, 100), DDRange.new(1, 2), DELTA1)
  end

  #--------------------------------

  DELTA2 =<<EOF
<superblock uuid="" time="1" transaction="0" data_block_size="128" nr_data_blocks="163840">
  <diff left="0" right="1">
    <same begin="0" length="160"/>
    <right_only begin="160" length="16"/>
  </diff>
</superblock>
EOF

  define_test :snap_with_single_block_difference2 do
    delta_test(DDRange.new(0, 10), DDRange.new(10, 11), DELTA2)
  end

  #--------------------------------

  DELTA3 =<<EOF
<superblock uuid="" time="1" transaction="0" data_block_size="128" nr_data_blocks="163840">
  <diff left="0" right="1">
    <right_only begin="144" length="16"/>
    <same begin="160" length="1440"/>
  </diff>
</superblock>
EOF

  define_test :snap_with_single_block_difference3 do
    delta_test(DDRange.new(10, 100), DDRange.new(9, 10), DELTA3)
  end

  #--------------------------------

  DELTA4 =<<EOF
<superblock uuid="" time="1" transaction="0" data_block_size="128" nr_data_blocks="163840">
  <diff left="0" right="1">
    <right_only begin="80" length="80"/>
    <different begin="160" length="80"/>
    <same begin="240" length="80"/>
  </diff>
</superblock>
EOF

  define_test :snap_with_single_block_difference4 do
    delta_test(DDRange.new(10, 20), DDRange.new(5, 15), DELTA4)
  end

  #--------------------------------

  DELTA5 =<<EOF
<superblock uuid="" time="1" transaction="0" data_block_size="128" nr_data_blocks="163840">
  <diff left="0" right="1">
    <same begin="160" length="80"/>
    <different begin="240" length="80"/>
    <right_only begin="320" length="80"/>
  </diff>
</superblock>
EOF

  define_test :snap_with_single_block_difference5 do
    delta_test(DDRange.new(10, 20), DDRange.new(15, 25), DELTA5)
  end

end

#----------------------------------------------------------------
