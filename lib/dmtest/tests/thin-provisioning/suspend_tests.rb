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
            thin1.pause do
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
end

#----------------------------------------------------------------
