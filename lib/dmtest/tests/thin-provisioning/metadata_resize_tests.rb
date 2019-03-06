require 'dmtest/device_mapper'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/status'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'
require 'rspec/expectations'

require 'pp'

#----------------------------------------------------------------

class MetadataResizeTests < ThinpTestCase
  include DiskUnits
  include Utils
  include TinyVolumeManager
  extend TestUtils

  def setup
    super
    @low_water_mark = 0 if @low_water_mark.nil?
    @data_block_size = 128

    @tvm = VM.new
    @tvm.add_allocation_volume(@data_dev)
    
    @thin_count = 10
    @thin_size = gig(10)
  end

  tag :thinp_target

  # FIXME: replace all these explicit pool tables with stacks

  define_test :resize_no_io do
    md_size = meg(1)
    data_size = meg(100)
    @tvm.add_volume(linear_vol('metadata', md_size))
    @tvm.add_volume(linear_vol('data', data_size))

    with_devs(@tvm.table('metadata'),
              @tvm.table('data')) do |md, data|
      wipe_device(md, 8)

      table = Table.new(ThinPoolTarget.new(data_size, md, data, @data_block_size, @low_water_mark))
      with_dev(table) do |pool|

        [1, 3, 7, 31, 67, 511, 1023].map {|s| meg(s)}.each do |step|
          status = PoolStatus.new(pool)
          status.total_metadata_blocks.should == md_size / 8

          @tvm.resize('metadata', md_size + step)
          pool.pause do
            md.pause do
              table = @tvm.table('metadata')
              md.load(table)
            end
          end

          status = PoolStatus.new(pool)
          status.total_metadata_blocks.should == (md_size + step) / 8
          md_size += step
        end
      end
    end
  end

  define_test :resize_no_io_with_extra_checking do
    md_size = meg(1)
    data_size = meg(100)
    @tvm.add_volume(linear_vol('metadata', md_size))
    @tvm.add_volume(linear_vol('data', data_size))

    with_devs(@tvm.table('metadata'),
              @tvm.table('data')) do |md, data|
      wipe_device(md, 8)

      [1, 3, 7, 31, 67, 511, 1023].map {|s| meg(s)}.each do |step|
        @tvm.resize('metadata', md_size + step)
        md.pause do
          table = @tvm.table('metadata')
          md.load(table)
        end

        table = Table.new(ThinPoolTarget.new(data_size, md, data, @data_block_size, @low_water_mark))
        with_dev(table) do |pool|
          status = PoolStatus.new(pool)
          status.total_metadata_blocks.should == (md_size + step) / 8
          md_size += step
        end
      end
    end
  end

  define_test :resize_with_io do
    data_size = gig(1)
    @tvm.add_volume(linear_vol('metadata', meg(1)))
    @tvm.add_volume(linear_vol('data', data_size))

    with_devs(@tvm.table('metadata'),
              @tvm.table('data')) do |md, data|
      wipe_device(md, 8)

      table = Table.new(ThinPoolTarget.new(data_size, md, data, @data_block_size, @low_water_mark))
      with_dev(table) do |pool|
        status1 = PoolStatus.new(pool)

        with_new_thin(pool, meg(50), 0) do |thin|
          fork {wipe_device(thin)}
          ProcessControl.sleep 5

          @tvm.resize('metadata', meg(2))
          thin.pause do
            pool.pause do
              md.pause do
                table = @tvm.table('metadata')
                md.load(table)
              end
            end
          end

          Process.wait
        end

        status2 = PoolStatus.new(pool)

        assert_equal(status1.total_metadata_blocks * 2, status2.total_metadata_blocks)
      end
    end
  end

  define_test :resize_after_exhaust do
    metadata_reserve = meg(32)
    data_size = [@tvm.free_space - metadata_reserve, gig(10)].min
    thin_size = data_size / 2   # because some data blocks may be misplaced during the abort
    metadata_size = k(512)

    @tvm.add_volume(linear_vol('data', data_size))
    @tvm.add_volume(linear_vol('metadata', metadata_size))

    with_devs(@tvm.table('metadata'),
              @tvm.table('data')) do |md, data|
      wipe_device(md, 8)

      table = Table.new(ThinPoolTarget.new(data_size, md, data, @data_block_size, @low_water_mark,
                                           true, true, true, false, true))
      with_dev(table) do |pool|
        with_new_thin(pool, thin_size, 0) do |thin|
          # There isn't enough metadata to provision the whole
          # device, so this will fail
          begin
            wipe_device(thin)
          rescue
            STDERR.puts "wipe_device failed as expected"
          end

          # Running out of metadata will have triggered read only mode
          PoolStatus.new(pool).options[:mode].should == :read_only
        end
      end

      ProcessControl.run("thin_check --clear-needs-check-flag #{md.path}")

      # Prove that we can bring up the pool at this point.  ie. before
      # we resize the metadata dev.
      with_dev(table) do |pool|
        # Then we resize the metadata dev
        metadata_size = metadata_size + meg(30)
        @tvm.resize('metadata', metadata_size)
        pool.pause do
          md.pause do
            md.load(@tvm.table('metadata'))
          end
        end

        # Now we can provision our thin completely
        with_thin(pool, thin_size, 0) do |thin|
          assert(write_mode?(pool))
          wipe_device(thin)
        end
      end
    end
  end

  #--------------------------------

  define_test :exhausting_metadata_space_aborts_to_ro_mode do
    md_blocks = 8
    md_size = 64 * md_blocks
    data_size = gig(2)

    @tvm.add_volume(linear_vol('metadata', md_size))
    @tvm.add_volume(linear_vol('data', data_size))

    with_devs(@tvm.table('metadata'),
              @tvm.table('data')) do |md, data|

      stack = PoolStack.new(@dm, data, md, :data_size => data_size, :block_size => @data_block_size,
                            :low_water_mark => @low_water_mark, :error_if_no_space => true)
      stack.activate do |pool|
        with_new_thin(pool, @volume_size, 0) do |thin|
          # We use capture because this doesn't raise ExitErrors
          _1, _2, err = ProcessControl.capture("dd if=/dev/zero of=#{thin.path} bs=4M")
          assert(err)
        end

        assert(read_only_mode?(pool))
      end

      stack.activate do |pool|
        # We should still be in read-only mode because of the
        # needs_check flag being set
        assert(read_only_mode?(pool))
      end
    end
  end

  # It's hard to predict how much metadata will be used by a
  # particular operation.  So the approach we'll take is to set up a
  # pool, do some work, query to see how much is used and then set the
  # thresholds appropriately.

  def _test_low_metadata_space_triggers_event
    md_blocks = 8
    md_size = 128 * md_blocks
    data_size = gig(2)

    @tvm.add_volume(linear_vol('metadata', md_size))
    @tvm.add_volume(linear_vol('data', data_size))

    with_devs(@tvm.table('metadata'),
              @tvm.table('data')) do |md, data|
      wipe_device(md, 8)

      table = Table.new(ThinPoolTarget.new(data_size, md, data, @data_block_size, @low_water_mark))
      with_dev(table) do |pool|
        with_new_thin(pool, @volume_size, 0) do |thin|
          # We want to do just enough io to take the metadata dev over
          # the threshold, _without_ running out of space.
          wipe_device(thin, 1024)
        end

        pp PoolStatus.new(pool)
      end
    end
  end

  #--------------------------------

  # This scenario was reported by Kabi
  define_test :thin_remove_works_after_resize do
    md_size = meg(2)
    data_size = meg(100)
    @tvm.add_volume(linear_vol('metadata', md_size))
    @tvm.add_volume(linear_vol('data', data_size))

    with_devs(@tvm.table('metadata'),
              @tvm.table('data')) do |md, data|
      wipe_device(md, 8)

      table = Table.new(ThinPoolTarget.new(data_size, md, data, @data_block_size, @low_water_mark))
      with_dev(table) do |pool|

        # Create a couple of thin volumes
        pool.message(0, "create_thin 0")
        pool.message(0, "create_thin 1")

        new_size = meg(256)

        status = PoolStatus.new(pool)
        status.total_metadata_blocks.should == md_size / 8

        @tvm.resize('metadata', new_size)
        pool.pause do
          md.pause do
            table = @tvm.table('metadata')
            md.load(table)
          end
        end

        # the first delete was causing the pool to flick into
        # read_only mode due to a failed commit, ...
        pool.message(0, "delete 0")

        status = PoolStatus.new(pool)

        status.total_metadata_blocks.should == new_size / 8
        status.options[:mode].should == :read_write

        # ... which then led to the second delete failing
        pool.message(0, "delete 1")
      end
    end
  end

  #--------------------------------

  # I'm trying to track down the metadata exhaustion/curruption bug

  def turn_on_bm_journal
    File.open('/sys/module/dm_thin_pool/parameters/block_manager_journal', 'w') do |f|
      f.write('/dev/sdd')
    end
  end

  def monitor_metadata(pool)
    tid = Thread.new(pool) do |pool|
      loop do
        status = PoolStatus.new(pool)
        break if status.total_metadata_blocks == status.used_metadata_blocks
        STDERR.puts "metadata #{status.used_metadata_blocks}/#{status.total_metadata_blocks}"
        sleep 10
      end

      STDERR.puts "*** Crash the machine now ***"
      sleep 12345
    end

    tid
  end
  
  def with_stack(thin_count, thin_size, opts = {}, &block)
    md_size = meg(12)

    metadata_vg = VM.new
    metadata_vg.add_allocation_volume(@metadata_dev)
    metadata_vg.add_volume(linear_vol('metadata', md_size))

    data_vg = VM.new
    data_vg.add_allocation_volume(@data_dev)
    data_vg.add_volume(linear_vol('data', thin_count * thin_size))

    with_devs(metadata_vg.table('metadata'), data_vg.table('data')) do |md, data|
      stack = PoolStack.new(@dm, data, md, opts)
      block.call(stack)
    end
  end

  def new_stack(thin_count, thin_size, &block)
    with_stack(thin_count, thin_size, :zero => false, :error_if_no_space => true, &block)
  end

  def reopen_stack(thin_count, thin_size, &block)
    with_stack(thin_count, thin_size, :zero => false, :error_if_no_space => true, :format => false, &block)
  end

  # We kick off each thread at 1 minute intervals to slowly ramp up usage
  def p_work(pool, thin_size, thin_ids, &block)
    tids = []
    thin_ids.each do |thin_id|
      tids << Thread.new(pool, thin_size, thin_id) do |pool, thin_size, thin_id|
        block.call(pool, thin_size, thin_id)
      end
      sleep 5
    end

    tids.each {|t| t.join}
  end

  FS_TYPE = :xfs
  
  def work_load(pool, thin_size, thin_id)
    STDERR.puts "in work_load"
    10.times do
      with_new_thin(pool, thin_size, thin_id) do |thin|
        fs = FS::file_system(FS_TYPE, thin)
        report_time("formatting #{thin_id}", STDERR) do
          fs.format()
        end

	dir = "./test-mountpoint-#{thin_id}"
	
        fs.with_mount(dir, :discard => false) do
          report_time("cloning #{thin_id}", STDERR) do
            repo = Git.clone('/root/linux-github', "#{dir}/linux")
          end

          report_time("delete dir #{thin_id}", STDERR) do
            ProcessControl.run("rm -rf #{dir}/linux")
          end

          report_time("fstrim #{thin_id}", STDERR) do
            ProcessControl.run("fstrim #{dir}")
          end
        end
      end

      report_time("delete dev #{thin_id}", STDERR) do
        pool.message(0, "delete #{thin_id}")
      end
    end

    STDERR.puts "#{thin_id} finished"
  end

  def work_load_bad(pool, thin_size, thin_id)
    STDERR.puts "in work_load"
    10.times do
      with_new_thin(pool, thin_size, thin_id) do |thin|
        report_time("wipe device #{thin_id}", STDERR) do
          wipe_device(thin)
        end
      end
      
      report_time("delete dev #{thin_id}", STDERR) do
        pool.message(0, "delete #{thin_id}")
      end
    end

    STDERR.puts "#{thin_id} finished"
  end

  define_test :thin_exhaust_metadata_big do
    turn_on_bm_journal
    
    new_stack(@thin_count, @thin_size) do |stack|
      stack.activate do |pool|
      	monitor = monitor_metadata(pool)
      	
        thin_ids = Array (0..(@thin_count - 1))
        begin
          p_work(pool, @thin_size, thin_ids) do |p, s, t|
            work_load(p, s, t)
          end
        ensure
    	  monitor.join
    	end
        STDERR.puts "all mutators finished"
      end
    end

    # Just double checking that with_stack is deterministic
    reopen_stack(@thin_count, @thin_size) do |stack|
      stack.activate do |pool|
      end
    end
  end

  define_test :recover_after_crash do
    reopen_stack(@thin_count, @thin_size) do |stack|
      ProcessControl.run("thin_check #{stack.metadata_dev}")
      ProcessControl.run("thin_dump #{stack.metadata_dev}")
    end
  end
end

#----------------------------------------------------------------
