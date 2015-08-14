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
  extend TestUtils

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

  define_test :hold_release_cycle_empty_pool do
    with_standard_pool(@size) do |pool|
      assert_root_unset(pool)
      pool.message(0, "reserve_metadata_snap")
      assert_root_set(pool)
      pool.message(0, "release_metadata_snap")
      assert_root_unset(pool)
    end
  end

  define_test :cannot_hold_twice do
    with_standard_pool(@size) do |pool|
      pool.message(0, "reserve_metadata_snap")
      assert_raise(ExitError) do
        pool.message(0, "reserve_metadata_snap")
      end
    end
  end

  define_test :cannot_release_twice do
    with_standard_pool(@size) do |pool|
      pool.message(0, "reserve_metadata_snap")
      pool.message(0, "release_metadata_snap")

      assert_raise(ExitError) do
        pool.message(0, "release_metadata_snap")
      end
    end
  end

  define_test :no_initial_hold do
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

  define_test :held_root_benchmark do
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        time_wipe("fully provision: thin1", thin1)
        time_wipe("provisioned: thin1", thin1)

        pool.message(0, "reserve_metadata_snap")
      end
    end

    with_standard_pool(@size, :format => false) do |pool|
      with_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        time_wipe("provisioned, held: thin1", thin1)
        time_wipe("fully provision, held: thin2", thin2)
      end
    end

    # tearing down the pool so we can force a thin_check

    with_standard_pool(@size, :format => false) do |pool|
      with_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        pool.message(0, "release_metadata_snap")

        time_wipe("provisioned: thin1", thin1)
        time_wipe("provisioned: thin2", thin2)
      end
    end
  end

  define_test :held_dump do
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

  define_test :thin_check_passes_with_a_held_root do
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
        held_metadata = read_held_root(pool, @metadata_dev)
      end

      # Tearing down the pool triggers a thin_check automatically
    end
  end
end
