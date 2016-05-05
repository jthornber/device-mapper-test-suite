require 'dmtest/blktrace'
require 'dmtest/discard_limits'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/status'
require 'dmtest/thinp-test'
require 'dmtest/thread-utils'
require 'dmtest/xml_format'
require 'dmtest/test-utils'
require 'set'

#----------------------------------------------------------------

module DiscardMixin
  include Utils
  include XMLFormat
  include BlkTrace
  include TinyVolumeManager
  include DiskUnits

  def setup
    super

    @size = 2097152 * 2         # sectors

    @blocks_per_dev = div_up(@volume_size, @data_block_size)
    @volume_size = @blocks_per_dev * @data_block_size # we want whole blocks for these tests
  end

  def read_metadata
    dump_metadata(@metadata_dev) do |xml_path|
      File.open(xml_path, 'r') do |io|
        read_xml(io)            # this is the return value
      end
    end
  end

  def with_dev_md(md, thin_id, &block)
    md.devices.each do |dev|
      next unless dev.dev_id == thin_id

      return block.call(dev)
    end
  end

  def assert_no_mappings(md, thin_id)
    with_dev_md(md, thin_id) do |dev|
      assert_equal(0, dev.mapped_blocks)
      assert_equal([], dev.mappings)
    end
  end

  def assert_fully_mapped(md, thin_id)
    with_dev_md(md, thin_id) do |dev|
      assert_equal(@blocks_per_dev, dev.mapped_blocks)
    end
  end

  # The block should be a predicate that says whether a given block
  # should be provisioned.
  def check_provisioned_blocks(md, thin_id, size, &block)
    provisioned_blocks = Array.new(size, false)

    with_dev_md(md, thin_id) do |dev|
      dev.mappings.each do |m|
        m.origin_begin.upto(m.origin_begin + m.length - 1) do |b|
          provisioned_blocks[b] = true
        end
      end
    end

    0.upto(size - 1) do |b|
      assert_equal(block.call(b), provisioned_blocks[b],
                   "bad provision status for block #{b}")
    end
  end

  def used_data_blocks(pool)
    s = PoolStatus.new(pool)
    STDERR.puts "pool status metadata(#{s.used_metadata_blocks}/#{s.total_metadata_blocks}) data(#{s.used_data_blocks}/#{s.total_data_blocks})"
    s.used_data_blocks
  end

  def assert_used_blocks(pool, count)
    assert_equal(count, used_data_blocks(pool))
  end

  def discard(thin, b, len)
    b_sectors = b * @data_block_size
    len_sectors = len * @data_block_size

    thin.discard(b_sectors, [len_sectors, @volume_size - b_sectors].min)
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  #--------------------------------

  module ClassMethods
    def define_test_over_bs(name, *bs, &block)
      bs.each do |block_size|
        define_method("test_#{name}_bs#{block_size}".intern) do
          @data_block_size = block_size
          @blocks_per_dev = div_up(@volume_size, @data_block_size)
          @volume_size = @blocks_per_dev * @data_block_size # we want whole blocks for these tests

          yield(block_size, @volume_size)
        end
      end
    end
  end

  def check_discard_passdown_enabled(pool, data_dev)
    with_new_thin(pool, @volume_size, 0) do |thin|
      wipe_device(thin, @data_block_size)

      traces, _ = blktrace_complete(thin, data_dev) do
        discard(thin, 0, 1)
      end

      assert_discards(traces[0], 0,  @data_block_size)
      assert_discards(traces[1], 0,  @data_block_size)
    end
  end

  def check_discard_passdown_disabled(pool, data_dev)
    with_new_thin(pool, @volume_size, 0) do |thin|
      wipe_device(thin, @data_block_size)

      traces, _ = blktrace_complete(thin, data_dev) do
        discard(thin, 0, 1)
      end

      assert_discards(traces[0], 0,  @data_block_size)
      assert(traces[1].empty?)
    end
  end
end

#----------------------------------------------------------------

class DiscardQuickTests < ThinpTestCase
  include DiscardMixin
  include DiskUnits
  extend TestUtils

  def unmapping_check(discardable, passdown)
    if discardable
      with_discardable_pool(@size, :discard_passdown => passdown) do |pool, fd_dev|
        data_limits = DiscardLimits.new(fd_dev.to_s)
        pool_limits = DiscardLimits.new(pool.to_s)

        pool_limits.supported.should be_true
        pool_limits.granularity.should == data_limits.granularity

        with_new_thin(pool, @volume_size, 0) do |thin|
          thin_limits = DiscardLimits.new(thin.to_s)
          thin_limits.supported.should be_true

          if passdown
            # FIXME: when partial discards go in we should change this to be data_limits.granularity
            thin_limits.granularity.should == @data_block_size * 512
          else
            thin_limits.granularity.should == @data_block_size * 512
          end

          wipe_device(thin)
          assert_used_blocks(pool, @blocks_per_dev)
          thin.discard(0, @volume_size)
          assert_used_blocks(pool, 0)
        end
      end
    else
      with_non_discardable_pool(@size, :discard_passdown => passdown) do |pool, fd_dev|
        data_limits = DiscardLimits.new(fd_dev.to_s)
        pool_limits = DiscardLimits.new(pool.to_s)

        pool_limits.supported.should be_false

        with_new_thin(pool, @volume_size, 0) do |thin|
          thin_limits = DiscardLimits.new(thin.to_s)

          thin_limits.supported.should be_true
          thin_limits.granularity.should == @data_block_size * 512

          wipe_device(thin)
          assert_used_blocks(pool, @blocks_per_dev)
          thin.discard(0, @volume_size)
          assert_used_blocks(pool, 0)
        end
      end
    end

    md = read_metadata
    assert_no_mappings(md, 0)
  end

  define_test :discard_unmaps_with_passdown_discardable_pool do
    unmapping_check(true, true)
  end

  define_test :discard_unmaps_with_no_passdown_discardable_pool do
    unmapping_check(true, false)
  end

  define_test :discard_unmaps_with_passdown_non_discardable_pool do
    unmapping_check(false, true)
  end

  define_test :discard_unmaps_with_no_passdown_non_discardable_pool do
    unmapping_check(false, false)
  end

  define_test :discard_no_unmap_with_discard_disabled_discardable_pool do
    with_discardable_pool(@size, :discard => false) do |pool, fd_dev|
      with_new_thin(pool, @volume_size, 0) do |thin|
        thin_limits = DiscardLimits.new(thin.to_s)
        thin_limits.supported.should be_false

        wipe_device(thin)
        assert_used_blocks(pool, @blocks_per_dev)

        caught = false
        begin
          thin.discard(0, @volume_size)
        rescue
          caught = true
        end

        assert(caught)
        assert_used_blocks(pool, @blocks_per_dev)
      end
    end
  end

  define_test :discard_no_unmap_with_discard_disabled_non_discardable_pool do
    with_non_discardable_pool(@size, :discard => false) do |pool, fd_dev|
      with_new_thin(pool, @volume_size, 0) do |thin|
        thin_limits = DiscardLimits.new(thin.to_s)
        thin_limits.supported.should be_false

        wipe_device(thin)
        assert_used_blocks(pool, @blocks_per_dev)

        caught = false
        begin
          thin.discard(0, @volume_size)
        rescue
          caught = true
        end

        assert(caught)
        assert_used_blocks(pool, @blocks_per_dev)
      end
    end
  end

  #--------------------------------

  define_test :discard_empty_device do
    @size = dev_size(@data_dev)
    @volume_size = @size
    with_discardable_pool(@size, :discard_passdown => false) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        report_time("discarding volume of size #{@volume_size}", STDERR) do
          thin.discard(0, @volume_size)
        end

#  DiscardMixin::define_test_over_bs(:discard_empty_device, 128, 192)  do |block_size, volume_size|
#    with_standard_pool(@size, :block_size => block_size) do |pool|
#      with_new_thin(pool, volume_size, 0) do |thin|
#        thin.discard(0, volume_size)

        assert_used_blocks(pool, 0)
      end
    end

    md = read_metadata
    assert_no_mappings(md, 0)
  end

  define_test :discard_fully_provisioned_device do
    with_discardable_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin, thin2|
        wipe_device(thin)
        wipe_device(thin2)
        assert_used_blocks(pool, 2 * @blocks_per_dev)
        thin.discard(0, @volume_size)
        assert_used_blocks(pool, @blocks_per_dev)
      end
    end

    md = read_metadata
    assert_no_mappings(md, 0)
    assert_fully_mapped(md, 1)
  end

  define_test :discard_fully_provisioned_device_benchmark do
    @size = [dev_size(@data_dev), gig(80)].min
    @volume_size = @size

    STDERR.puts "@size = #{@size}"

    xml_file = "discard_test.xml"
    ProcessControl.run("thinp_xml create --nr-thins 1 --nr-mappings #{@size / @data_block_size} --block-size #{@data_block_size} > #{xml_file}")
    ProcessControl.run("thin_restore -o #{@metadata_dev} -i #{xml_file}")
    STDERR.puts "restored metadata"

    with_discardable_pool(@size, :format => false, :discard_passdown => true) do |pool, data_dev|
      with_thin(pool, @volume_size, 0) do |thin|
        STDERR.puts "about to discard"
        report_time("discarding provisioning volume of size #{@volume_size}", STDERR) do
          thin.discard(0, @volume_size)
        end
      end
    end

    md = read_metadata
    assert_no_mappings(md, 0)
  end

  define_test :discard_a_fragmented_device do
    @size = [dev_size(@data_dev), gig(80)].min
    @volume_size = @size

    # FIXME: factor out
    nr_data_blocks = @size / @data_block_size
    superblock = Superblock.new("uuid", 0, 1, 128, nr_data_blocks)
    mappings = []
    0.upto(nr_data_blocks - 1) do |n|
      if n.even?
        mappings << Mapping.new(n, n / 2, 1, 0)
      end
    end
    devices = [Device.new(0, mappings.size, 0, 0, 0, mappings)]
    metadata = Metadata.new(superblock, devices)

    Utils::with_temp_file('metadata_xml') do |file|
      write_xml(metadata, file)
      file.flush
      file.close
      restore_metadata(file.path, @metadata_dev)
    end
    ProcessControl.run("thin_check #{@metadata_dev}")
    STDERR.puts "restored metadata"

    with_discardable_pool(@size, :format => false, :discard_passdown => true) do |pool|
      with_thin(pool, @volume_size, 0) do |thin|
        STDERR.puts "about to discard"
        report_time("discarding fragmented volume of size #{@volume_size}", STDERR) do
          thin.discard(0, @volume_size)
        end
      end
    end

    md = read_metadata
    assert_no_mappings(md, 0)
  end

  define_test :delete_fully_provisioned_device do
    @size = [dev_size(@data_dev), gig(80)].min
    @volume_size = @size

    xml_file = "discard_test.xml"
    ProcessControl.run("thinp_xml create --nr-thins 1 --nr-mappings #{@size / @data_block_size} --block-size #{@data_block_size} > #{xml_file}")
    ProcessControl.run("thin_restore -o #{@metadata_dev} -i #{xml_file}")
    STDERR.puts "restored metadata"

    with_discardable_pool(@size, :format => false) do |pool|
      report_time("deleting provisioning volume of size #{@volume_size}", STDERR) do
        pool.message(0, "delete 0")
      end
    end
  end

  define_test :discard_single_block do
    with_discardable_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)
        assert_used_blocks(pool, @blocks_per_dev)
        thin.discard(0, @data_block_size)
        assert_used_blocks(pool, @blocks_per_dev - 1)
      end
    end

    md = read_metadata
    check_provisioned_blocks(md, 0, @blocks_per_dev) do |b|
      b == 0 ? false : true
    end
  end

  # If a block is shared we can unmap the block, but must not pass the
  # discard down to the underlying device.
  define_test :discard_to_a_shared_block_doesnt_get_passed_down do
    with_discardable_pool(@size) do |pool, data_dev|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin, @data_block_size)

        assert_used_blocks(pool, 1)

        with_new_snap(pool, @volume_size, 1, 0, thin) do |snap|
          assert_used_blocks(pool, 1)
          traces, _ = blktrace_complete(thin, snap, data_dev) do
            thin.discard(0, @data_block_size)
          end

          thin_trace, snap_trace, data_trace = traces
          event = Event.new([:discard], 0, @data_block_size)
          assert(thin_trace.member?(event))
          assert(!snap_trace.member?(event))
          assert(!data_trace.member?(event))

          assert_used_blocks(pool, 1)
        end
      end
    end
  end

  define_test :discard_to_a_previously_shared_block_does_get_passed_down do
    with_discardable_pool(@size , :format => true, :discard_passdown => true) do |pool, data_dev|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin, @data_block_size)

        assert_used_blocks(pool, 1)

        with_new_snap(pool, @volume_size, 1, 0, thin) do |snap|
          assert_used_blocks(pool, 1)
        end

        pool.message(0, "delete 1")

        traces, _ = blktrace_complete(thin, data_dev) do
          thin.discard(0, @data_block_size)
          sleep 1               # FIXME: shouldn't need this
        end

        thin_trace, data_trace = traces
        event = Event.new([:discard], 0, @data_block_size)
        assert(thin_trace.member?(event))
        assert(data_trace.member?(event))

        assert_used_blocks(pool, 0)
      end
    end
  end

  define_test :discard_partial_blocks do
    with_discardable_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)

        thin.discard(0, 120)
        thin.discard(56, 160)
      end
    end

    md = read_metadata
    assert_fully_mapped(md, 0)
  end

  define_test :discard_same_blocks do
    @data_block_size = 128

    with_discardable_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin, 256)

        1000.times do
          thin.discard(0, 128)
        end

        assert_used_blocks(pool, 1)
      end
    end
  end

  define_test :discard_with_background_io do
    with_discardable_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        tid = Thread.new(thin) do |thin|
          wipe_device(thin)
        end

        sleep(10)

        1000.times do
          s = rand(@blocks_per_dev - 1)
          s_len = 1 + rand(5)

          discard(thin, s, s_len)
        end

        tid.join
      end
    end
  end

  define_test :disable_discard do
    with_discardable_pool(@size, :discard => false) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin, 4)

        discards = DiscardLimits.new("#{thin}")
        discards.max_bytes.should == 0
        discards.granularity.should == 0
        discards.supported.should be_false

        assert_raise(Errno::EOPNOTSUPP) do
          thin.discard(0, @data_block_size)
        end
      end
    end
  end

  # we don't allow people to change their minds about top level
  # discard support.
  define_test :change_discard_with_reload_fails do
    with_discardable_pool(@size, :discard => true) do |pool, data_dev|
      assert_raise(ExitError) do
        table = Table.new(ThinPoolTarget.new(@size, @metadata_dev, data_dev,
                                             @data_block_size, @low_water_mark, false, false, false))
        pool.load(table)
      end
    end

    with_standard_pool(@size, :discard => false) do |pool, data_dev|
      assert_raise(ExitError) do
        table = Table.new(ThinPoolTarget.new(@size, @metadata_dev, data_dev,
                                             @data_block_size, @low_water_mark, false, true, false))
        pool.load(table)
      end
    end
  end

  define_test :discard_origin_does_not_effect_snap do
    with_discardable_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)
        assert_used_blocks(pool, @blocks_per_dev)

        with_new_snap(pool, @volume_size, 1, 0, thin) do |snap|
          assert_used_blocks(pool, @blocks_per_dev)
        end

        thin.discard(0, @volume_size)
        assert_used_blocks(pool, @blocks_per_dev)
      end
      assert_used_blocks(pool, @blocks_per_dev)
    end
  end

  define_test :discard_past_the_end_fails do
    with_discardable_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)

        failed = false
        begin
          thin.discard(0, 2 * @volume_size)
        rescue
          failed = true
        end

        assert(failed)
      end
    end
  end
end

#----------------------------------------------------------------

class DiscardSlowTests < ThinpTestCase
  include DiscardMixin
  extend TestUtils

  define_test :discard_alternate_blocks do
    with_discardable_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)

        b = 0
        while b < @blocks_per_dev
          thin.discard(b * @data_block_size, @data_block_size)
          b += 2
        end
      end
    end

    md = read_metadata
    check_provisioned_blocks(md, 0, @blocks_per_dev) {|b| b.odd?}
  end

  def do_discard_random_sectors(duration)
    jobs = ThreadedJobs.new

    start = Time.now
    threshold_blocks = @blocks_per_dev / 3

    with_standard_pool(@size, :discard_passdown => false) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        jobs.add_job(2, thin) {|thin| wipe_device(thin)}
        jobs.add_job(2, thin) do |thin|
          1000.times do
            s_len = 1 + rand(1024)
            s = rand(@blocks_per_dev - s_len)

            discard(thin, s, s_len)
          end
        end

        sleep(60)
        jobs.stop
      end
    end
  end

  define_test :discard_random_sectors do
    do_discard_random_sectors(10 * 60)
  end

  def with_stacked_pools(levels, &block)
    # create 2 metadata devs
    tvm = VM.new
    tvm.add_allocation_volume(@metadata_dev)

    md_size = tvm.free_space / 2
    tvm.add_volume(linear_vol('md1', md_size))
    tvm.add_volume(linear_vol('md2', md_size))

    with_devs(tvm.table('md1'),
              tvm.table('md2')) do |md1, md2|
      wipe_device(md1, 8)
      wipe_device(md2, 8)

      t1 = Table.new(ThinPoolTarget.new(@volume_size, md1, @data_dev, @data_block_size, 0, true, levels[:lower], levels[:lower_passdown]))
      with_dev(t1) do |lower_pool|
        with_new_thin(lower_pool, @volume_size, 0) do |lower_thin|
          t2 = Table.new(ThinPoolTarget.new(@volume_size, md2, lower_thin, @data_block_size, 0, true, levels[:upper], levels[:upper_passdown]))
          with_dev(t2) do |upper_pool|
            with_new_thin(upper_pool, @volume_size, 0) do |upper_thin|
              block.call(lower_pool, lower_thin, upper_pool, upper_thin)
              sleep 1           # FIXME: sometimes the dev is still held open
            end
          end
        end
      end
    end
  end

  #
  # set up 2 level pool stack to provison and discard a thin device
  # at the upper level and allow for enabling/disabling
  # discards and discard_passdown at any level
  #
  def do_discard_levels(levels = Hash.new)
    with_stacked_pools(levels) do |lpool, lthin, upool, uthin|
      # provison the whole thin dev and discard half of its blocks_used
      total = div_up(@volume_size, @data_block_size)
      discard_count = total / 2
      remaining = total - discard_count

      wipe_device(uthin)
      assert_equal(total, used_data_blocks(upool))
      assert_equal(total, used_data_blocks(lpool))

      # assert results for combinations
      if (levels[:upper])
        0.upto(discard_count - 1) {|b| discard(uthin, b, 1)}
        assert_equal(remaining, used_data_blocks(upool))
      else
        assert_raise(Errno::EOPNOTSUPP) do
          discard(uthin, 0, discard_count)
        end

        assert_equal(total, used_data_blocks(upool))
      end

      if (levels[:lower])
        if (levels[:upper_passdown])
          assert_equal(remaining, used_data_blocks(lpool))
        else
          assert_equal(total, used_data_blocks(lpool))
        end
      else
        assert_equal(total, used_data_blocks(lpool))
      end
    end
  end

  define_test :discard_lower_both_upper_both do
    do_discard_levels(:lower => true,
                      :lower_passdown => true,
                      :upper => true,
                      :upper_passdown => true)
  end

  define_test :discard_lower_none_upper_both do
    do_discard_levels(:lower => false,
                      :lower_passdown => false,
                      :upper => true,
                      :upper_passdown => true)
  end

  define_test :discard_lower_both_upper_none do
    do_discard_levels(:lower => true,
                      :lower_passdown => true,
                      :upper => false,
                      :upper_passdown => false)
  end

  define_test :discard_lower_none_upper_none do
    do_discard_levels(:lower => false,
                      :lower_passdown => false,
                      :upper => false,
                      :upper_passdown => false)
  end

  define_test :discard_lower_both_upper_discard do
    do_discard_levels(:lower => true,
                      :lower_passdown => true,
                      :upper => true,
                      :upper_passdown => false)
  end

  define_test :discard_lower_discard_upper_both do
    do_discard_levels(:lower => true,
                      :lower_passdown => false,
                      :upper => true,
                      :upper_passdown => true)
  end

  def create_and_delete_lots_of_files(dev, fs_type)
    fs = FS::file_system(fs_type, dev)
    fs.format
    fs.with_mount("./mnt1", :discard => true) do
      ds = Dataset.read(LP('compile-bench-datasets/dataset-unpatched'))
      Dir.chdir('mnt1') do
        Dir.mkdir('linux')
        Dir.chdir('linux') do
          10.times do
            STDERR.write "."
            ds.apply
            ProcessControl.run("sync")
            ProcessControl.run("rm -rf *")
            ProcessControl.run("sync")
          end
        end
      end
    end
  end

  def do_discard_test(fs_type)
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        create_and_delete_lots_of_files(thin, fs_type)
      end
    end
  end

  define_test :fs_discard_ext4 do
    do_discard_test(:ext4)
  end

  define_test :fs_discard_xfs do
    do_discard_test(:xfs)
  end

  define_test :discard_after_out_of_space do
    with_standard_pool(@size, :error_if_no_space => true) do |pool|
      with_new_thin(pool, @size * 2, 0) do |thin|
        begin
          wipe_device(thin)
        rescue
        end
        s = PoolStatus.new(pool)
        s.options[:mode].should == :out_of_data_space

        thin.discard(0, @size)
        s = PoolStatus.new(pool)
        s.used_data_blocks.should == 0
        s.options[:mode].should == :read_write
      end
    end
  end

  def discard_with_fstrim_passdown(passdown, fs_type)
    dir = "./mnt1"
    @size = gig(4)
    file_size = @size / 20
    files = (0..9).reduce([]) {|memo, obj| memo << "file_#{obj}"}

    with_discardable_pool(@size, :error_if_no_space => true, :discard_passdown => passdown) do |pool|
      with_new_thin(pool, @size * 2, 0) do |thin|
        fs = FS::file_system(fs_type, thin)
        fs.format
        fs.with_mount(dir, :discard => false) do
          Dir.chdir(dir) do
            files.each do |f|
              ProcessControl.run("dd if=/dev/zero of=#{f} bs=1M count=#{file_size / meg(1)} oflag=direct")
            end

            ProcessControl.run("sync")

            files.each do |f|
              ProcessControl.run("rm #{f}")
            end
          end

          ProcessControl.run("sync")

          $log.info "used data blocks before: #{PoolStatus.new(pool).used_data_blocks}"
          ProcessControl.run("fstrim -v #{dir}")
          $log.info "used data blocks after: #{PoolStatus.new(pool).used_data_blocks}"

          s = PoolStatus.new(pool)
          s.used_data_blocks.should < 5000
          s.options[:mode].should == :read_write
        end
      end
    end
  end

  define_tests_across(:discard_with_fstrim_passdown, [true, false], [:xfs, :ext4])
end

#----------------------------------------------------------------

class FakeDiscardTests < ThinpTestCase
  include DiscardMixin
  extend TestUtils

  def check_discard_thin_working(thin)
    wipe_device(thin, @data_block_size)
    traces, _ = blktrace(thin) do
      discard(thin, 0, 1)
    end

    assert_discards(traces[0], 0,  @data_block_size)
  end

  define_test :enable_passdown do
    with_fake_discard(:granularity => 128, :max_discard_sectors => 512) do |fd_dev|
      with_custom_data_pool(fd_dev, @size, :discard_passdown => true) do |pool|
        check_discard_passdown_enabled(pool, fd_dev)
      end
    end
  end

  define_test :disable_passdown do
    with_fake_discard(:granularity => 128, :max_discard_sectors => 512) do |fd_dev|
      with_custom_data_pool(fd_dev, @size, :discard_passdown => false) do |pool|
        check_discard_passdown_disabled(pool, fd_dev)
      end
    end
  end

  define_test :pool_granularity_matches_data_dev do
    # when discard_passdown is enabled
    pool_bs = 512
    @data_block_size = pool_bs
    with_fake_discard(:granularity => 128, :max_discard_sectors => pool_bs) do |fd_dev|
      with_custom_data_pool(fd_dev, @size, :discard_passdown => true,
                            :block_size => pool_bs) do |pool|

        assert_equal(fd_dev.queue_limits.discard_granularity,
                     pool.queue_limits.discard_granularity)
        assert_equal(pool.queue_limits.discard_max_bytes, pool_bs * 512)

        # verify discard passdown is still enabled
        check_discard_passdown_enabled(pool, fd_dev)
      end
    end
  end
end

#----------------------------------------------------------------
