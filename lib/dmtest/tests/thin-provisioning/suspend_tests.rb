require 'dmtest/dataset'
require 'dmtest/fs'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'
require 'timeout'
require 'pp'

# these added for the dataset stuff
require 'fileutils'

#----------------------------------------------------------------

class SuspendTests < ThinpTestCase
  include Tags
  include Utils
  include DiskUnits

  def test_suspend_pool_no_thins
    with_standard_pool(@size) do |pool|
      pool.pause {}
    end
  end

  def test_suspend_pool_no_active_thins
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
      end

      pool.pause {}
    end
  end

  def test_suspend_pool_active_thins_no_io
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        pool.pause {}
      end
    end
  end

  def test_suspend_pool_suspended_thin
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        thin1.pause do
          pool.pause {}
        end
      end
    end
  end

  def test_suspend_pool_resume_thin
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        pool.pause do
          sleep 1

          thin1.resume

          timed_out = false

          begin
            Timeout::timeout(5) do
              wipe_device(thin1, 8)
            end
          rescue Timeout::Error
            timed_out = true
          rescue
            assert(false)
          end

          timed_out.should be_true
        end
      end
    end
  end

  def test_suspend_pool_concurrent_suspend
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        pool.suspend
        tid = Thread.new do
          sleep 5
          pool.resume
        end

        timed_out = false
        begin
          Timeout::timeout(10) do
            thin1.pause do # blocks waiting for pool.resume
              wipe_device(thin1, 8)
            end
          end
        rescue Timeout::Error
          timed_out = true
        rescue
          assert(false)
        end

        tid.join

        timed_out.should be_true
      end
    end
  end

  def test_suspend_pool_after_suspend_thin
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        thin1.pause do

          pool.pause {}

          timed_out = false
          begin
            Timeout::timeout(5) do
              wipe_device(thin1, 8)
            end
          rescue Timeout::Error
            timed_out = true
          rescue
            assert(false)
          end

          timed_out.should be_true
        end
      end
    end
  end

  # term1:
  # dmsetup suspend pool
  # dmsetup suspend thin1
  #                                                 term2:
  # (blocks waiting for internal suspend to clear)  # dmsetup resume pool
  #
  # dmsetup resume thin1
  def test_wait_on_bit_during_suspend
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        # trigger internal suspend of pool's active thin targets
        pool.suspend

        tid = Thread.new do
          sleep 10
          pool.resume
        end

        timed_out = false
        begin
          Timeout::timeout(1) do
            thin1.pause do # blocks waiting for internal resume via pool.resume
            end
          end
        rescue Timeout::Error
          timed_out = true
        rescue
          assert(false)
        end

        timed_out.should be_true
        sleep 10
        thin1.pause do
        end

        tid.join
      end
    end
  end

  # term1:
  # dmsetup suspend thin1
  # dmsetup suspend pool
  # dmsetup resume thin1
  #                                                 term2:
  # (blocks waiting for internal suspend to clear)  # dmsetup resume pool
  #
  # (finally thin1 resumes)
  def test_wait_on_bit_during_resume
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        thin1.suspend
        # trigger _nested_ internal suspend of thin1 target
        pool.suspend

        tid = Thread.new do
          sleep 10
          pool.resume
        end

        timed_out = false
        begin
          Timeout::timeout(1) do
            thin1.resume # blocks waiting for internal resume via pool.resume
          end
        rescue Timeout::Error
          timed_out = true
        rescue
          assert(false)
        end

        timed_out.should be_true
        sleep 10
        thin1.resume

        tid.join
      end
    end
  end

  def test_nested_internal_suspend_using_inactive_table
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin1, thin2|
        # load duplicate thin table into thin1's inactive slot
        thin_table = thin1.active_table
        thin1.load(thin_table)

        # trigger internal suspend of pool's active thin targets
        # (which _includes_ the inactive table for thin1 due to thin_ctr
        #  adding the new thin device to the pool's active thins list)
        pool.pause do
          timed_out = false

          begin
            Timeout::timeout(5) do
              # skip suspend, allow resume to initiate suspend
              thin1.resume
            end
          rescue Timeout::Error
            timed_out = true
          rescue
            assert(false)
          end

          timed_out.should be_true
        end # pool resume triggers internal resume for active thin devices

        thin1.resume
        wipe_device(thin1, 8)
      end
    end
  end

end

#----------------------------------------------------------------
