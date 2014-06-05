require 'dmtest/disk-units'
require 'dmtest/fs'
require 'dmtest/log'
require 'dmtest/pattern_stomper'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/tvm'
require 'dmtest/utils'

#----------------------------------------------------------------

class ExternalSnapStack
  include DM
  include DM::LexicalOperators
  include DiskUnits
  include Utils
  include ThinpTestMixin

  attr_accessor :md, :origin, :thin

  def initialize(dm, metadata_dev, data_dev, opts = {})
    @dm = dm
    @metadata_dev = metadata_dev
    @data_dev = data_dev
    @opts = opts

    @md_tvm = TinyVolumeManager::VM.new
    @md_tvm.add_allocation_volume(@metadata_dev, 0, dev_size(@metadata_dev))
    @md_tvm.add_volume(linear_vol('md', metadata_size))

    @data_tvm = TinyVolumeManager::VM.new
    @data_tvm.add_allocation_volume(@data_dev, 0, dev_size(@data_dev))
    @data_tvm.add_volume(linear_vol('origin', origin_size))
    @data_tvm.add_volume(linear_vol('pool_data', pool_data_size))
  end

  def metadata_size
    @opts.fetch(:metadata_size, meg(4))
  end

  def origin_size
    @opts.fetch(:origin_size, meg(512))
  end

  def thin_size
    @opts.fetch(:thin_size, origin_size)
  end

  def pool_data_size
    @opts.fetch(:pool_data_size, gig(2))
  end

  def pool_table(md, pool_data)
    zero = @opts.fetch(:zero, true)
    discard = @opts.fetch(:discard, true)
    discard_pass = @opts.fetch(:discard_passdown, true)
    read_only = @opts.fetch(:read_only, false)
    error_if_no_space = @opts.fetch(:error_if_no_space, false)
    block_size = @opts.fetch(:block_size, 128)
    low_water_mark = @opts.fetch(:low_water_mark, 0)

    Table.new(ThinPoolTarget.new(dev_size(pool_data), md, pool_data,
                                 block_size, low_water_mark,
                                 zero, discard, discard_pass, read_only,
                                 error_if_no_space))
  end

  def activate_origin(&block)
    with_dev(@data_tvm.table('origin')) do |origin|
      @origin = origin
      block.call(origin)
    end
  end

  def activate_thin(&block)
    with_devs(@md_tvm.table('md'),
              @data_tvm.table('pool_data')) do |md, pool_data|

      wipe_device(md, 8)

      @pool_stack = PoolStack.new(@dm, pool_data, md, @opts)
      @pool_stack.activate do |pool|
        with_new_thin(pool, thin_size, 0, :origin => @origin) do |thin|
          block.call(@origin, thin)
        end
      end
    end
  end
end

#----------------------------------------------------------------

class ExternalOriginTests < ThinpTestCase
  include Tags
  include TinyVolumeManager
  include Utils
  include DiskUnits

  def setup
    super
  end

  #--------------------------------

  tag :thinp_target

  def do_pattern_stamp_test(opts = {})
    opts[:pool_data_size] ||= gig(4)
    opts[:origin_size] ||= gig(1)

    s = ExternalSnapStack.new(@dm, @metadata_dev, @data_dev, opts)

    s.activate_origin do |origin|
      origin_stomper = PatternStomper.new(origin.path, @data_block_size, :needs_zero => true)

      s.activate_thin do |thin|
        origin_stomper.stamp(20)

        cache_stomper = origin_stomper.fork(thin.path)
        cache_stomper.verify(0, 1)

        cache_stomper.stamp(10)
        cache_stomper.verify(0, 2)

        origin_stomper.verify(0, 1)
      end
    end
  end

  def test_snap_equal_size
    do_pattern_stamp_test
  end

  def test_snap_smaller_than_origin
    do_pattern_stamp_test(:thin_size => meg(512))
  end

  def test_snap_bigger_than_origin
    do_pattern_stamp_test(:thin_size => gig(2))
  end

  def test_snap_fractional_tail_block
    do_pattern_stamp_test(:origin_size => gig(1) + 16)
  end
end

#----------------------------------------------------------------
