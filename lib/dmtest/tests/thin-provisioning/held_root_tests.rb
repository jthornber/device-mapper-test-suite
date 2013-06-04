require 'config'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/status'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/xml_format'

#----------------------------------------------------------------

class HeldRootTests < ThinpTestCase
  include Tags
  include Utils
  include XMLFormat

  def get_root(pool)
    status = PoolStatus.new(pool)
    status.held_root
  end

  def assert_root_set(pool)
    root = get_root(pool)
    assert(!root.nil? && root != 0)
  end

  def assert_root_unset(pool)
    assert_equal(nil, get_root(pool))
  end

  #--------------------------------------------------------------

  def test_hold_release_cycle_empty_pool
    with_standard_pool(@size) do |pool|
      assert_root_unset(pool)
      pool.message(0, "reserve_metadata_snap")
      assert_root_set(pool)
      pool.message(0, "release_metadata_snap")
      assert_root_unset(pool)
    end
  end

  def test_cannot_hold_twice
    with_standard_pool(@size) do |pool|
      pool.message(0, "reserve_metadata_snap")
      assert_raise(ExitError) do
        pool.message(0, "reserve_metadata_snap")
      end
    end
  end

  def test_cannot_release_twice
    with_standard_pool(@size) do |pool|
      pool.message(0, "reserve_metadata_snap")
      pool.message(0, "release_metadata_snap")

      assert_raise(ExitError) do
        pool.message(0, "release_metadata_snap")
      end
    end
  end

  def test_no_initial_hold
    with_standard_pool(@size) do |pool|
      assert_raise(ExitError) do
        pool.message(0, "release_metadata_snap")
      end
    end
  end

  def time_wipe(desc, dev)
    report_time(desc) do
      wipe_device(dev)
    end
  end

  def test_held_root_benchmark
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        time_wipe("fully provision: thin1", thin1)
        time_wipe("provisioned: thin1", thin1)

        pool.message(0, "reserve_metadata_snap")
        time_wipe("provisioned, held: thin1", thin1)
        time_wipe("fully provision, held: thin2", thin2)
        time_wipe("provisioned, held: thin2", thin2)
      end
    end

    # tearing down the pool so we can force a thin_check

    with_standard_pool(@size) do |pool|
      with_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        pool.message(0, "release_metadata_snap")

        time_wipe("provisioned: thin1", thin1)
        time_wipe("provisioned: thin2", thin2)
      end
    end
  end

  def test_held_dump
    held_metadata = nil

    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)
        pool.message(0, "create_snap 1 0")
        pool.message(0, "reserve_metadata_snap")
        wipe_device(thin)          # forcing the held root and live metadata to diverge

        held_metadata = read_held_root(pool, @metadata_dev)

        pool.message(0, "release_metadata_snap")
      end
    end

    final_metadata = read_metadata(@metadata_dev)

    left, common, right = compare_thins(held_metadata, final_metadata, 0)
    assert_equal([], common)
    assert_equal(1, left.length)
    assert_equal(1, right.length)
    assert_equal(0, left[0].origin_begin)
    assert_equal(0, right[0].origin_begin)

    nr_blocks = @volume_size / @data_block_size
    assert_equal(nr_blocks, left[0].length)
    assert_equal(nr_blocks, right[0].length)
  end
end
