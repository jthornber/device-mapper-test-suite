require 'dmtest/blktrace'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

class ToolsTests < ThinpTestCase
  include Utils
  include BlkTrace

  def setup
    super
  end

  def forbidden_on_live_metadata(cmd)
    s = EraStack.new(@dm, @metadata_dev, @data_dev, {})

    s.activate do
      s.era.message(0, "take_metadata_snap")
      assert_raises(ProcessControl::ExitError) do
        ProcessControl.run(cmd)
      end
    end
  end

  def allowed_on_live_metadata(cmd)
    s = EraStack.new(@dm, @metadata_dev, @data_dev, {})

    s.activate do
      s.era.message(0, "take_metadata_snap")
      ProcessControl.run(cmd)
    end
  end

  def test_you_cannot_run_check_on_live_metadata
    forbidden_on_live_metadata("era_check #{@metadata_dev}")
  end

  def _test_you_cannot_run_restore_on_a_live_metadata
  end

  def test_you_cannot_dump_live_metadata
    forbidden_on_live_metadata("era_dump #{@metadata_dev}")
  end

  def _test_you_can_dump_a_metadata_snapshot
    allowed_on_live_metadata("era_dump --metadata-snap #{@metadata_dev}")
  end
end

#----------------------------------------------------------------
