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

  #--------------------------------

  # die loopback, die!
  def with_loopback_pool(&block)
    dir = "./mnt1"
    loop_file = "#{dir}/loop_file"
    loop_dev = "/dev/loop0"
    loop_size = gig(4)

    fs = FS::file_system(:ext4, @data_dev)
    fs.format
    fs.with_mount(dir, :discard => true) do
      ProcessControl.run("fallocate -l #{loop_size * 512} #{loop_file}")
      ProcessControl.run("losetup #{loop_dev} #{loop_file}")
      
      begin
        with_custom_data_pool(loop_dev, loop_size, :discard_passdown => true, &block)
      ensure
        ProcessControl.run("losetup -d #{loop_dev}")
      end
    end
  end

  # bz #1195506
  def test_discard_then_delete_thin
    with_loopback_pool do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        tid = Thread.new(thin) do |thin|
          10.times do
            wipe_device(thin)
            thin.discard(0, @volume_size)
          end
        end

        sleep 15

        10.times do
          thin.pause_noflush do
            failed = false
            begin
              # this should fail since the device is active
              pool.message(0, "delete 0")
            rescue
              failed = true
            end

            failed.should be_true
          end
        end

        tid.join
      end
    end
  end
end

#----------------------------------------------------------------
