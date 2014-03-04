require 'dmtest/device_mapper'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/status'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'
require 'rspec/expectations'

require 'pp'

#----------------------------------------------------------------

class MetadataResizeTests < ThinpTestCase
  include DiskUnits
  include Tags
  include Utils
  include TinyVolumeManager

  def setup
    super
    @low_water_mark = 0 if @low_water_mark.nil?
    @data_block_size = 128

    @tvm = VM.new
    @tvm.add_allocation_volume(@data_dev, 0, dev_size(@data_dev))
  end

  tag :thinp_target

  def test_resize_metadata_no_io
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

  def test_resize_metadata_with_io
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

  def test_resize_metadata_after_exhaust
    n = 10

    metadata_reserve = meg(32)
    data_size = @tvm.free_space - metadata_reserve
    metadata_size = k(512)
    metadata_step = k(256)

    @tvm.add_volume(linear_vol('data', data_size))
    @tvm.add_volume(linear_vol('metadata', metadata_size))

    with_devs(@tvm.table('metadata'),
              @tvm.table('data')) do |md, data|
      wipe_device(md, 8)

      # FIXME: :error_if_out_of_space should not be neccessary, bios
      # that would cause provisioning should _always_ be errored if in
      # read-only mode.  Kernel bug.
      table = Table.new(ThinPoolTarget.new(data_size, md, data, @data_block_size, @low_water_mark,
                                           true, true, true, false, true))
      with_dev(table) do |pool|
        with_new_thin(pool, data_size, 0) do |thin|
          1.upto(n - 1) do |step|
            STDERR.puts "metadata_size = #{metadata_size / 2}k"

            # There isn't enough metadata to provision the whole
            # device, so this will fail
            begin
              wipe_device(thin)
            rescue
              STDERR.puts "wipe_device failed as expected"
            end

            # Running out of metadata will have triggered read only mode
            PoolStatus.new(pool).options[:mode].should == :read_only

            STDERR.puts "resizing..."
            metadata_size = metadata_size + metadata_step
            @tvm.resize('metadata', metadata_size)

            thin.pause do
              pool.pause do
                md.pause do
                  md.load(@tvm.table('metadata'))
                end
                
                # We reload to force the pool out of read-only mode
                pool.load(table)
              end
            end
          end
        end
      end
    end
  end

  #--------------------------------

  def test_exhausting_metadata_space_causes_fail_mode
    md_blocks = 8
    md_size = 64 * md_blocks
    data_size = gig(2)

    @tvm.add_volume(linear_vol('metadata', md_size))
    @tvm.add_volume(linear_vol('data', data_size))

    with_devs(@tvm.table('metadata'),
              @tvm.table('data')) do |md, data|
      wipe_device(md, 8)

      stack = PoolStack.new(@dm, data, md, :data_size => data_size, :block_size => @data_block_size,
                            :low_water_mark => @low_water_mark, :error_if_no_space => true)
      stack.activate do |pool|
        with_new_thin(pool, @volume_size, 0) do |thin|
          # We use capture because this doesn't raise ExitErrors
          _1, _2, err = ProcessControl.capture("dd if=/dev/zero of=#{thin.path} bs=4M")
          assert(err)
        end

        assert(read_only_or_fail_mode(pool))
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
  def test_thin_remove_works_after_resize
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

#----------------------------------------------------------------
