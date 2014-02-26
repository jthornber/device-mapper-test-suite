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
  include TinyVolumeManager

  def setup
    super
    @low_water_mark = 0
    @data_block_size = 128
  end


  def wait_until_out_of_data(pool)
    # wait until available space has been used
    pool.event_tracker.wait do
      status = PoolStatus.new(pool)
      status.options[:mode] == :out_of_data_space
    end
  end

  def wipe_expecting_error(dev)
    failed = false
    begin
      wipe_device(dev)
    rescue
      failed = true
    end

    failed.should be_true
  end

  #--------------------------------

  tag :thinp_target

  def test_out_of_data_space_errors_immediately_if_requested
    with_standard_pool(@volume_size / 2, :error_if_no_space => true) do |pool|
      failed = false

      with_new_thin(pool, @volume_size, 0) do |thin|
        begin
          wipe_device(thin)
        rescue
          failed = true
        end
      end

      failed.should be_true
      status = PoolStatus.new(pool)
      status.options[:mode].should == :out_of_data_space
    end
  end

  def test_out_of_data_space_times_out
    with_standard_pool(@volume_size / 2, :error_if_no_space => false) do |pool|
      failed = false

      with_new_thin(pool, @volume_size, 0) do |thin|
        begin
          wipe_device(thin)
        rescue
          failed = true
        end
      end

      failed.should be_true
      status = PoolStatus.new(pool)
      status.options[:mode].should == :read_only

      # FIXME: the needs_check flag should _not_ be set.
    end
  end

  def test_resize_after_OODS_error_immediately
    tvm = VM.new
    tvm.add_allocation_volume(@data_dev, 0, dev_size(@data_dev))

    @size = @volume_size / 2
    tvm.add_volume(linear_vol('data', @volume_size / 2))

    with_dev(tvm.table('data')) do |data|
      wipe_device(@metadata_dev, 8)

      table = Table.new(ThinPoolTarget.new(@size, @metadata_dev, data,
                                           @data_block_size, @low_water_mark,
                                           true, true, true, false, true))

      with_dev(table) do |pool|
        with_new_thin(pool, @volume_size, 0) do |thin|
          wipe_expecting_error(thin)

          thin.pause_noflush do
            # new size of the pool/data device
            @size *= 4

            # resize the underlying data device
            tvm.resize('data', @size)
            data.pause do
              data.load(tvm.table('data'))
            end

            # resize the pool
            pool.pause do
              table2 = Table.new(ThinPoolTarget.new(@size, @metadata_dev, data,
                                                    @data_block_size, @low_water_mark,
                                                    true, true, true, false, true))
              pool.load(table2)
            end

            status = PoolStatus.new(pool)
            status.options[:mode].should == :read_write
          end
        end
      end
    end
  end

  def test_resize_after_OODS_held_io
    tvm = VM.new
    tvm.add_allocation_volume(@data_dev, 0, dev_size(@data_dev))

    @size = @volume_size / 2
    tvm.add_volume(linear_vol('data', @volume_size / 2))

    with_dev(tvm.table('data')) do |data|
      wipe_device(@metadata_dev, 8)

      table = Table.new(ThinPoolTarget.new(@size, @metadata_dev, data,
                                           @data_block_size, @low_water_mark))

      with_dev(table) do |pool|
        with_new_thin(pool, @volume_size, 0) do |thin|
          tid = Thread.new(thin) do |thin|
            # If this errors then the exception _will_ be reported
            wipe_device(thin)
          end

          wait_until_out_of_data(pool)

          STDERR.puts "about to suspend thin"
          thin.pause_noflush do
            STDERR.puts "suspended thin"
            # new size of the pool/data device
            @size *= 4

            # resize the underlying data device
            tvm.resize('data', @size)
            data.pause do
              data.load(tvm.table('data'))
            end

            # resize the pool
            pool.pause do
              table2 = Table.new(ThinPoolTarget.new(@size, @metadata_dev, data,
                                                    @data_block_size, @low_water_mark))
              pool.load(table2)
            end
          end

          tid.join
        end
      end
    end

  end

  #--------------------------------

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
        tid = Thread.new(thin) do thin
          wipe_device(thin)
          STDERR.puts "wipe completed"
        end

        2.upto(n) do |i|
          wait_until_out_of_data(pool)

          table = Table.new(ThinPoolTarget.new(i * target_step, @metadata_dev, @data_dev,
                                               @data_block_size, @low_water_mark))

          STDERR.puts "about to suspend thin"
          thin.pause_noflush do
            STDERR.puts "about to suspend pool"
            STDERR.puts "reload #{i}"
            pool.load(table)
            pool.resume
          end
        end

        tid.join
      end

      # suspend/resume cycle should _not_ cause read-write -> read-only!
      STDERR.puts "last pause"
      pool.pause {}

      status = PoolStatus.new(pool)
      status.options[:mode].should == :read_write

      # remove the created thin
      pool.message(0, 'delete 0')
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
