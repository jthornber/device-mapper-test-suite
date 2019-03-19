require 'dmtest/device_mapper'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/status'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'
require 'rspec/expectations'
require 'thread'
require 'tmpdir'

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
end

#------------------------------

class ThinAllocator
  def initialize()
    @lock = Mutex.new
    @available = Set.new
    @borrowed = Set.new
    @next_thin_id = 0
  end

  def thin_count
    @lock.synchronize do
      @available.size + @borrowed.size
    end
  end

  def _new_tid
    @lock.synchronize do
      r = @next_thin_id
      @next_thin_id = @next_thin_id + 1
      @borrowed.add(r)
      r
    end
  end

  def _get_tid
    @lock.synchronize do
      if @available.size == 0
        raise "no free thins"
      end
      
      index = rand(@available.size)
      @available.each do |t|
        if index == 0
          @available.delete(t)
          @borrowed.add(t)
          return t
        else
          index = index - 1
        end         
      end
    end
  end

  def _put_tid(t)
    @lock.synchronize do
      @available.add(t)
      @borrowed.delete(t)
    end
  end

  def borrow_existing(&block)
    t = _get_tid
    begin
      block.call(t)
    ensure
      _put_tid(t)
    end
  end

  def borrow_new(&block)
    t = _new_tid
    begin
      block.call(t)
    ensure
      _put_tid(t)
    end
  end

  def delete_thin
    t = _get_tid
    @lock.synchronize do
      @borrowed.delete(t)
    end
    t
  end
end

class MountPointAllocator
  def initialize(mps)
    @lock = Mutex.new
    @mps = mps
  end

  def _borrow
    @lock.synchronize do
      if @mps.empty?
        raise "no mor mount points"
      end

      @mps.shift
    end
  end

  def _return(mp)
    @lock.synchronize do
      @mps << mp
    end
  end

  def with_mount_point(&block)
    mp = _borrow
    begin 
      block.call(mp)
    ensure
      _return(mp)
    end
  end
end

#------------------------------------

class MetadataExhaustionTests < ThinpTestCase
  include DiskUnits
  include Utils
  include TinyVolumeManager
  extend TestUtils

  NR_THREADS = 8
  
  def setup
    super
    @low_water_mark = 0 if @low_water_mark.nil?
    @data_block_size = 128

    @thin_count = 10
    @thin_size = gig(10)
    @allocator = ThinAllocator.new

    mps = (0..9).map {|n| "test-mount-point-#{n}"}
    @mp_allocator = MountPointAllocator.new(mps)
  end

  def percent(a, b)
    if b == 0
      0
    else
      (a * 100) / b
    end
  end

  def monitor_metadata(pool)
    tid = Thread.new(pool) do |pool|
      loop do
        status = PoolStatus.new(pool)
        break if status.total_metadata_blocks == status.used_metadata_blocks
        
        md = percent(status.used_metadata_blocks, status.total_metadata_blocks)
        d = percent(status.used_data_blocks, status.total_data_blocks)
        STDERR.puts "metadata #{md}%, data #{d}%"
        sleep 10
      end

      STDERR.puts "*** Crash the machine now ***"
      sleep 12345
    end

    tid
  end
  
  def with_stack(thin_count, thin_size, opts = {}, &block)
    md_size = meg(24)

    #metadata_vg = VM.new
    #metadata_vg.add_allocation_volume(@metadata_dev)
    #metadata_vg.add_volume(linear_vol('metadata', md_size))

    # Let's try having both the metadata and data on the same device
    data_vg = VM.new
    data_vg.add_allocation_volume(@data_dev)
    data_vg.add_volume(linear_vol('metadata', md_size))
    data_vg.add_volume(linear_vol('data', (thin_count * thin_size) - md_size))

    with_devs(data_vg.table('metadata'), data_vg.table('data')) do |md, data|
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

  FS_TYPE = :xfs

  def format_thin(thin_dev)
    fs = FS::file_system(FS_TYPE, thin_dev)
    fs.format()
  end

  def with_mount(thin_dev, &block)
    @mp_allocator.with_mount_point do |dir|
      fs = FS::file_system(FS_TYPE, thin_dev)
      fs.with_mount(dir, :discard => false) do
        block.call(dir)
      end
    end
  end

  def with_git(thin_dev, &block)
    with_mount(thin_dev) do |dir|
      git = Git.new("#{dir}/linux")
      block.call(git)
    end
  end
  

  def setup_initial_thin(thin_dev)
    format_thin(thin_dev)

    with_mount(thin_dev) do |dir|
      Git.clone('/root/linux-github', "#{dir}/linux")
    end
  end

  TAGS = %w(v2.6.12 v2.6.13 v2.6.14 v2.6.15 v2.6.16 v2.6.17 v2.6.18 v2.6.19
            v2.6.20 v2.6.21 v2.6.22 v2.6.23 v2.6.24 v2.6.25 v2.6.26 v2.6.27 v2.6.28
            v2.6.29 v2.6.30 v2.6.31 v2.6.32 v2.6.33 v2.6.34 v2.6.35 v2.6.36 v2.6.37
            v2.6.38 v2.6.39 v3.0 v3.1 v3.2)

  def action_new_snap(pool)
    # we borrow the origin, so we know it's not active
    @allocator.borrow_existing do |origin|
      @allocator.borrow_new do |t|
        STDERR.puts "creating snap #{origin} -> #{t}"
        pool.message(0, "create_snap #{t} #{origin}")
      end
    end
  end

  def action_del_snap(pool)
    t = @allocator.delete_thin
    STDERR.puts "deleting #{t}"
    pool.message(0, "delete #{t}")
  end

  def action_io(pool)
    @allocator.borrow_existing do |t|
      with_thin(pool, @thin_size, t) do |thin_dev|
        with_git(thin_dev) do |git|
          1.times do
            tag = TAGS.sample
            STDERR.puts "thin #{t}: mutating"
            git.checkout(tag)
          end
        end
      end
    end
  end

  def above_threshold(val, total, percent_threshold)
    if total == 0
      true
    else
      ((val * 100.0) / total) >= percent_threshold
    end
  end
  
  def low_on_space(pool)
    s = PoolStatus.new(pool)
    above_threshold(s.used_metadata_blocks, s.total_metadata_blocks, 75) ||
      above_threshold(s.used_data_blocks, s.total_data_blocks, 80)
  end

  def choose_option(pool)
    if @allocator.thin_count < NR_THREADS
      action_new_snap(pool)
    elsif rand(10) == 0
      action_del_snap(pool)
    elsif rand(3) == 0
      action_new_snap(pool)
    else
      action_io(pool)
    end
  end

  def trace(n)
    STDERR.puts n.to_s
  end

  def mutate(pool)
    40.times do |n|
      choose_option(pool)
    end
  end
  
  define_test :thin_exhaust_metadata_big do
    new_stack(@thin_count, @thin_size) do |stack|
      stack.activate do |pool|
      	monitor = monitor_metadata(pool)

        @allocator.borrow_new do |t|
    	with_new_thin(pool, @thin_size, t) do |thin_dev|
            setup_initial_thin(thin_dev)
          end
        end

        NR_THREADS.times do
          action_new_snap(pool)
        end

        begin
          threads = []
          (0..(NR_THREADS - 1)).each do |n|
            threads << Thread.new(pool) {|pool| mutate(pool)}
          end

	  threads.each {|tid| tid.join}
      	rescue => e
  	  STDERR.puts "caught exception #{e}"
          monitor.join
        end
        	
        STDERR.puts "all mutators finished"
      end
    end
  end

  define_test :recover_after_crash do
    reopen_stack(@thin_count, @thin_size) do |stack|
      ProcessControl.run("thin_check #{stack.metadata_dev}")
      ProcessControl.run("thin_dump #{stack.metadata_dev}")

      # We can bring up the pool, but it will have immediately fallen
      # back to read_only mode.
      stack.activate do |pool|
        pp PoolStatus.new(pool)
        assert(read_only_mode?(pool))
        status = PoolStatus.new(pool)
        status.needs_check.should be_true
      end

      # use tools to clear needs_check mode
      ProcessControl.run("thin_check --clear-needs-check-flag #{metadata}")

      # Now we should be able to run in write mode
      with_dev(table) do |pool|
        assert(write_mode?(pool))
      end
    end
  end
end

