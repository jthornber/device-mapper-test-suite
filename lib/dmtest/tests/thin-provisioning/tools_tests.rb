require 'dmtest/blktrace'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'
require 'dmtest/tests/thin-provisioning/metadata-generator'

#----------------------------------------------------------------

class ToolsTests < ThinpTestCase
  include Utils
  include BlkTrace
  include MetadataGenerator
  extend TestUtils

  def setup
    super
  end

  def forbidden_on_live_metadata(cmd)
    with_standard_pool(@size) do |pool|
      pool.message(0, "reserve_metadata_snap")

      with_new_thin(pool, @volume_size, 0) do |thin|
        assert_raises(ProcessControl::ExitError) do
          ProcessControl.run(cmd)
        end
      end
    end
  end

  def allowed_on_live_metadata(cmd)
    with_standard_pool(@size) do |pool|
      pool.message(0, "reserve_metadata_snap")

      with_new_thin(pool, @volume_size, 0) do |thin|
        ProcessControl.run(cmd)
      end
    end
  end

  define_test :you_cannot_run_thin_check_on_live_metadata do
    forbidden_on_live_metadata("thin_check #{@metadata_dev}")
  end

  define_test :you_cannot_run_thin_restore_on_a_live_metadata do
    metadata = create_metadata(5, 1024, :linear_array)

    Utils::with_temp_file('metadata_xml') do |file|
      write_xml(metadata, file)
      file.flush
      file.close

      forbidden_on_live_metadata("thin_restore -i #{file.path} -o #{@metadata_dev}")
    end
  end

  define_test :you_cannot_dump_live_metadata do
    forbidden_on_live_metadata("thin_dump #{@metadata_dev}")
  end

  define_test :you_can_dump_a_metadata_snapshot do
    allowed_on_live_metadata("thin_dump --metadata-snap #{@metadata_dev}")
  end

  #--------------------------------

  DUMP1 =<<EOF
<superblock uuid="" time="0" transaction="0" data_block_size="128" nr_data_blocks="0">
  <device dev_id="0" mapped_blocks="0" transaction="0" creation_time="0" snap_time="0">
  </device>
  <device dev_id="1" mapped_blocks="0" transaction="0" creation_time="0" snap_time="0">
  </device>
</superblock>
EOF

  DUMP2 =<<EOF
<superblock uuid="" time="0" transaction="0" data_block_size="128" nr_data_blocks="0">
  <device dev_id="0" mapped_blocks="16384" transaction="0" creation_time="0" snap_time="0">
    <range_mapping origin_begin="0" data_begin="0" length="16384" time="0"/>
  </device>
  <device dev_id="1" mapped_blocks="0" transaction="0" creation_time="0" snap_time="0">
  </device>
</superblock>
EOF

  DUMP3 =<<EOF
<superblock uuid="" time="0" transaction="0" data_block_size="128" nr_data_blocks="0">
  <device dev_id="0" mapped_blocks="16384" transaction="0" creation_time="0" snap_time="0">
    <range_mapping origin_begin="0" data_begin="0" length="16384" time="0"/>
  </device>
  <device dev_id="1" mapped_blocks="16384" transaction="0" creation_time="0" snap_time="0">
    <range_mapping origin_begin="0" data_begin="16384" length="16384" time="0"/>
  </device>
</superblock>
EOF

  def check_metadata_snap(pool, txt)
    metadata = nil
    expected = StringIO.new(txt)

    pool.message(0, "reserve_metadata_snap")
    begin
      Utils::with_temp_file('metadata_xml') do |file|
        ProcessControl::run("thin_dump -m #{@metadata_dev} > #{file.path}")
        file.rewind
        assert FileUtils.compare_stream(file, expected)
      end
    ensure
      pool.message(0, "release_metadata_snap")
    end
  end

  define_test :thin_dump_a_metadata_snap_of_an_active_pool do
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin, thin2|
        check_metadata_snap(pool, DUMP1)
        wipe_device(thin)
        check_metadata_snap(pool, DUMP2)
        wipe_device(thin2)
        check_metadata_snap(pool, DUMP3)
      end
    end
  end

  #--------------------------------

  # This test repeatedly takes metadata snapshots whilst a thin volume
  # is repeatedly created, provisioned and deleted. See bz 1286500.
  define_test :metadata_snap_stress_test do
    with_standard_pool(@size) do |pool|
      thread1 = Thread.new(pool) do |pool|
        10.times do
          with_new_thin(pool, @volume_size, 0) do |thin|
            wipe_device(thin)
          end

          pool.message(0, "delete 0")
        end
      end

      while thread1.alive? do
        sleep 1

        pool.message(0, "reserve_metadata_snap")
        pool.message(0, "release_metadata_snap")
      end
    end
  end
end

#----------------------------------------------------------------
