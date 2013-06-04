require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'timeout'

#----------------------------------------------------------------

class PoolResizeTests < ThinpTestCase
  include Tags
  include Utils

  def setup
    super
    @low_water_mark = 0
    @data_block_size = 128
  end

  tag :thinp_target

  def test_reload_no_io
    table = Table.new(ThinPoolTarget.new(@size, @metadata_dev, @data_dev,
                                         @data_block_size, @low_water_mark))

    with_dev(table) do |pool|
      pool.load(table)
      pool.resume
    end
  end

  def test_reload_io
    table = Table.new(ThinPoolTarget.new(20971520, @metadata_dev, @data_dev,
                                         @data_block_size, @low_water_mark))

    with_dev(table) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        fork {wipe_device(thin)}
        ProcessControl.sleep 5
        pool.load(table)
        pool.resume
        Process.wait
      end
    end
  end

  def test_resize_no_io
    target_step = @size / 8
    with_standard_pool(target_step) do |pool|
      2.upto(8) do |n|
        table = Table.new(ThinPoolTarget.new(n * target_step, @metadata_dev, @data_dev,
                                             @data_block_size, @low_water_mark))
        pool.load(table)
        pool.resume
      end
    end
  end

  def resize_io_many(n)
    target_step = round_up(@volume_size / n, @data_block_size)
    with_standard_pool(target_step) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        event_tracker = pool.event_tracker;

        fork {wipe_device(thin)}

        2.upto(n) do |i|
          # wait until available space has been used
          event_tracker.wait do
            status = PoolStatus.new(pool)
            status.used_data_blocks >= status.total_data_blocks - @low_water_mark
          end

          table = Table.new(ThinPoolTarget.new(i * target_step, @metadata_dev, @data_dev,
                                               @data_block_size, @low_water_mark))
          pool.load(table)
          pool.resume
        end

        Process.wait
        if $?.exitstatus > 0
          raise RuntimeError, "wipe sub process failed"
        end
      end
    end
  end

  def test_resize_io
    resize_io_many(8)
  end

  # I think the current behaviour is correct.  You should just avoid
  # opening the device on critical paths that do the resizing.  Even
  # if you do succeed in opening the dev, you can't close until after
  # the resize, or you'll hang again.
  def _test_close_on_out_of_data_doesnt_cause_hang
    size = 128
    opened = false

    with_standard_pool(size) do |pool|
      with_new_thin(pool, 256, 0) do |thin|
        event_tracker = pool.event_tracker;
        pid = fork {wipe_device(thin)}

        event_tracker.wait do
          status = PoolStatus.new(pool)
          status.used_data_blocks >= status.total_data_blocks - @low_water_mark
        end

        # dd may be blocked in the close call which flushes the
        # device.  Opening a device should always succeed, but the
        # close/sync may be causing it to block forever waiting for a
        # resize.  agk wishes to change this behaviour.
        f = nil
        begin
          f = File.open(thin.to_s)
          opened = true
        ensure
          # resize the pool so the wipe can complete.
          table = Table.new(ThinPoolTarget.new(256, @metadata_dev, @data_dev,
                                               @data_block_size, @low_water_mark))
          pool.load(table)
          pool.resume

          f.close unless f.nil?
        end
      end
    end

    Process.wait
    if $?.exitstatus > 0
      raise RuntimeError, "wipe sub process failed"
    end

    if !opened
      raise RuntimeError, "open failed"
    end
  end

  # see BZ #769921
  def test_ext4_runs_out_of_space
    # we create a pool with a really tiny data volume that wont be
    # able to complete a mkfs.
    with_standard_pool(16) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|

        event_tracker = pool.event_tracker;

        thin_fs = FS::file_system(:ext4, thin)
        fork {thin_fs.format}

        # FIXME: this is so common it should go into a utility lib
        event_tracker.wait do
          status = PoolStatus.new(pool)
          status.used_data_blocks >= status.total_data_blocks - @low_water_mark
        end

        # we're not sure what the development version of dmeventd was
        # doing to create the issue; some experiments to find out.
        pool.info

        # Resize the pool so the format can complete
        table = Table.new(ThinPoolTarget.new(@size, @metadata_dev, @data_dev,
                                             @data_block_size, @low_water_mark))
        pool.load(table)
        pool.resume
      end
    end

    Process.wait
    if $?.exitstatus > 0
      raise RuntimeError, "wipe sub process failed"
    end
  end

  # def test_reload_an_empty_table
  #   with_standard_pool(@size) do |pool|
  #     with_new_thin(pool, @volume_size, 0) do |thin|
  #       fork {wipe_device(thin)}

  #       sleep 5
  #       empty = Table.new
  #       pool.load(empty)
  #       pool.resume
  #     end
  #   end
  # end
end

#----------------------------------------------------------------
