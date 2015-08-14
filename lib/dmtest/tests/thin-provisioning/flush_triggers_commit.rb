require 'dmtest/blktrace'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# The periodic commit *may* interfere if the system is very
# heavily loaded.
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

# The kernel tracks which thin devices have changed and only commit
# metadata, triggered by a REQ_FLUSH or REQ_FUA, iff it has changed.
# These tests use blktrace on the metadata dev to spot the superblock
# being rewritten in these cases.
class FlushTriggersCommitTests < ThinpTestCase
  include Utils
  include BlkTrace
  extend TestUtils

  def flush(dev)
    File.open(dev.path, "w") do |file|
      file.fsync
    end
  end

  def committed?(dev, &block)
    flush(dev)

    traces, _ = blktrace(@metadata_dev) do
      block.call
      flush(dev)
    end

    traces[0].member?(Event.new([:write], 0, 8))
  end

  def assert_commit(dev, &block)
    flunk("expected commit") unless committed?(dev, &block)
  end

  def assert_no_commit(dev, &block)
    flunk("unexpected commit") if committed?(dev, &block)
  end

  def do_commit_checks(dev)
    # Force a block to be provisioned
    assert_commit(dev) do
      wipe_device(dev, @data_block_size)
    end

    # the first block is provisioned now, so there shouldn't be a
    # subsequent commit.
    assert_no_commit(dev) do
      wipe_device(dev, @data_block_size)
    end
  end

  define_test :commit_if_changed do
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        do_commit_checks(thin1)
        do_commit_checks(thin2)

        with_new_snap(pool, @volume_size, 2, 0) do |snap|
          do_commit_checks(thin1)
          do_commit_checks(snap)
        end
      end
    end
  end

  define_test :discard_triggers_commit do
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        wipe_device(thin1, @data_block_size)
        wipe_device(thin2, @data_block_size)

        assert_commit(thin1) do
          thin1.discard(0, @data_block_size)
        end

        do_commit_checks(thin1)

        assert_no_commit(thin2) do
          wipe_device(thin2, @data_block_size)
        end
      end
    end
  end
end
