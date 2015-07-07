require 'dmtest/blktrace'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/tests/thin-provisioning/metadata-generator'

#----------------------------------------------------------------

class ToolsTests < ThinpTestCase
  include Tags
  include Utils
  include BlkTrace
  include MetadataGenerator

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

  def test_you_cannot_run_thin_check_on_live_metadata
    forbidden_on_live_metadata("thin_check #{@metadata_dev}")
  end

  def test_you_cannot_run_thin_restore_on_a_live_metadata
    metadata = create_metadata(5, 1024, :linear_array)

    Utils::with_temp_file('metadata_xml') do |file|
      write_xml(metadata, file)
      file.flush
      file.close

      forbidden_on_live_metadata("thin_restore -i #{file.path} -o #{@metadata_dev}")
    end
  end

  def test_you_cannot_dump_live_metadata
    forbidden_on_live_metadata("thin_dump #{@metadata_dev}")
  end

  def test_you_can_dump_a_metadata_snapshot
    allowed_on_live_metadata("thin_dump --metadata-snap #{@metadata_dev}")
  end
end

#----------------------------------------------------------------
