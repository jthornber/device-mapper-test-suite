require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/status'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/tvm'

#----------------------------------------------------------------

class ImmutableTargetTests < ThinpTestCase
  include Tags
  include TinyVolumeManager
  include Utils

  def setup
    super

    @tvm = VM.new
    @tvm.add_allocation_volume(@data_dev)
    @volume_size = dev_size(@data_dev) / 4
    @metadata_dev_size = limit_metadata_dev_size(@volume_size)
  end

  tag :dm_core, :quick, :thinp_target, :linear_target, :stripe_target

  # sanity check
  def test_linear_can_replace_linear
    @tvm.add_volume(linear_vol('linear1', @volume_size))
    @tvm.add_volume(linear_vol('linear2', @volume_size))

    with_dev(@tvm.table('linear1')) do |dev|
      dev.load(@tvm.table('linear2'))
      dev.resume
    end
  end

  def test_multiple_linear_can_replace_linear
    @tvm.add_volume(linear_vol('linear1', @volume_size))
    @tvm.add_volume(linear_vol('linear2', @volume_size))

    with_dev(@tvm.table('linear1')) do |dev|
      # get the segment for linear2 and break up into sub segments.
      segs = @tvm.segments('linear2')
      raise RuntimeError, "unexpected number of segments" if segs.size != 1

      seg = segs[0]
      l2 = seg.length / 2
      table = Table.new(LinearTarget.new(l2, seg.dev, seg.offset),
                        LinearTarget.new(seg.length - l2, seg.dev, seg.offset + l2))

      dev.load(table)
      dev.resume
    end
  end

  def test_pool_can_replace_linear
    @tvm.add_volume(linear_vol('linear', @volume_size))
    @tvm.add_volume(linear_vol('pool-data', @volume_size))

    with_devs(@tvm.table('linear'),
              @tvm.table('pool-data')) do |dev, data|

      dev.load(Table.new(ThinPoolTarget.new(@metadata_dev_size, @metadata_dev, data, 128, 0)))
      dev.resume
    end
  end

  def test_pool_must_be_singleton
    @tvm.add_volume(linear_vol('metadata1', @metadata_dev_size))
    @tvm.add_volume(linear_vol('metadata2', @metadata_dev_size))
    @tvm.add_volume(linear_vol('data1', @volume_size))
    @tvm.add_volume(linear_vol('data2', @volume_size))

    with_devs(@tvm.table('metadata1'),
              @tvm.table('metadata2'),
              @tvm.table('data1'),
              @tvm.table('data2')) do |md1, md2, d1, d2|

      wipe_device(md1, 8)
      wipe_device(md2, 8)

      assert_raise(ExitError) do
        with_dev(Table.new(ThinPoolTarget.new(@volume_size, md1, d1, 128, 0),
                           ThinPoolTarget.new(@volume_size, md2, d2, 128, 0))) do |bad_pool|
          # shouldn't get here
        end
      end
    end
  end

  def test_pool_must_be_singleton2
    @tvm.add_volume(linear_vol('metadata', @metadata_dev_size))
    @tvm.add_volume(linear_vol('data', @volume_size))
    @tvm.add_volume(linear_vol('linear', @volume_size))

    with_devs(@tvm.table('metadata'),
              @tvm.table('data')) do |md, d, linear|

      wipe_device(md, 8)
      assert_raise(ExitError) do
        with_dev(Table.new(ThinPoolTarget.new(@volume_size, md, d, 128, 0),
                           *@tvm.table('linear').targets)) do |bad_pool|
          # shouldn't get here
        end
      end
    end
  end

  def test_same_pool_can_replace_pool
    @tvm.add_volume(linear_vol('md', @metadata_dev_size))
    @tvm.add_volume(linear_vol('data', @volume_size))

    with_devs(@tvm.table('md'),
              @tvm.table('data')) do |md, data|

      wipe_device(md, 8)
      table = Table.new(ThinPoolTarget.new(@volume_size, md, data, 128, 0))
      
      with_dev(table) do |pool|
        pool.load(table)
        pool.resume
      end
    end
  end

  def test_different_pool_cant_replace_pool
    @tvm.add_volume(linear_vol('metadata1', @metadata_dev_size))
    @tvm.add_volume(linear_vol('metadata2', @metadata_dev_size))
    @tvm.add_volume(linear_vol('data1', @volume_size))
    @tvm.add_volume(linear_vol('data2', @volume_size))

    with_devs(@tvm.table('metadata1'),
              @tvm.table('metadata2'),
              @tvm.table('data1'),
              @tvm.table('data2')) do |md1, md2, d1, d2|

      wipe_device(md1, 8)
      wipe_device(md2, 8)

      with_dev(Table.new(ThinPoolTarget.new(@volume_size, md1, d1, 128, 0))) do |pool|
        assert_raise(ExitError) do
          pool.load(Table.new(ThinPoolTarget.new(@volume_size, md2, d2, 128, 0)))
          pool.resume
        end
      end
    end
  end

  def test_pool_replacement_must_be_singleton
    @tvm.add_volume(linear_vol('md', @metadata_dev_size))
    @tvm.add_volume(linear_vol('data', @volume_size))
    @tvm.add_volume(linear_vol('linear', @volume_size))

    with_devs(@tvm.table('md'),
              @tvm.table('data')) do |md, data|

      wipe_device(md, 8)
      table = Table.new(ThinPoolTarget.new(@volume_size, md, data, 128, 0))
      
      with_dev(table) do |pool|
        seg = @tvm.segments('linear')[0]
        table = Table.new(ThinPoolTarget.new(@volume_size, md, data, 128, 0),
                          LinearTarget.new(@volume_size, seg.dev, seg.offset))
        assert_raise(ExitError) do
          pool.load(table)
        end
      end
    end
    
  end

  def test_pool_replace_cant_be_linear
    @tvm.add_volume(linear_vol('md', @metadata_dev_size))
    @tvm.add_volume(linear_vol('data', @volume_size))
    @tvm.add_volume(linear_vol('linear', @volume_size))

    with_devs(@tvm.table('md'),
              @tvm.table('data')) do |md, data|

      wipe_device(md, 8)
      table = Table.new(ThinPoolTarget.new(@volume_size, md, data, 128, 0))
      
      with_dev(table) do |pool|
        assert_raise(ExitError) do
          pool.load(@tvm.table('linear'))
        end
      end
    end
  end
end

#----------------------------------------------------------------
