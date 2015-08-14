require 'dmtest/blktrace'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/test-utils'

#----------------------------------------------------------------

class CreationTests < ThinpTestCase
  include Tags
  include TinyVolumeManager
  include Utils
  include BlkTrace
  extend TestUtils

  def setup
    super
    @max=1000
  end

  tag :thinp_target, :create_lots

  define_test :create_lots_of_empty_thins do
    with_standard_pool(@size) do |pool|
      0.upto(@max) {|id| pool.message(0, "create_thin #{id}")}
    end
  end

  define_test :create_lots_of_snaps do
    with_standard_pool(@size) do |pool|
      pool.message(0, "create_thin 0")
      1.upto(@max) {|id| pool.message(0, "create_snap #{id} 0")}
    end
  end

  define_test :create_lots_of_recursive_snaps do
    with_standard_pool(@size) do |pool|
      pool.message(0, "create_thin 0")
      1.upto(@max) {|id| pool.message(0, "create_snap #{id} #{id - 1}")}
    end
  end

  define_test :activate_thin_while_pool_suspended_fails do
    with_standard_pool(@size) do |pool|
      pool.message(0, "create_thin 0")
      pool.pause do
        begin
          with_thin(pool, @volume_size, 0) do |thin|
            # expect failure.
          end
        rescue
          failed = true
        end

        failed.should be_true
      end
    end
  end

  define_test :huge_block_size do
    size = @size
    data_block_size = 524288
    volume_size = 524288
    lwm = 5

    with_standard_pool(@size, :data_block_size => data_block_size) do |pool|
      with_new_thin(pool, volume_size, 0) {|thin| dt_device(thin)}
    end
  end

  tag :thinp_target, :quick

  define_test :non_power_of_2_data_block_size_fails do
    table = Table.new(ThinPoolTarget.new(@size, @metadata_dev, @data_dev,
                                         @data_block_size + 57, @low_water_mark))
    assert_bad_table(table)
  end

  define_test :too_small_data_block_size_fails do
    table = Table.new(ThinPoolTarget.new(@size, @metadata_dev, @data_dev,
                                         64, @low_water_mark))
    assert_bad_table(table)
  end

  define_test :too_large_data_block_size_fails do
    table = Table.new(ThinPoolTarget.new(@size, @metadata_dev, @data_dev,
                                         2**21 + 1, @low_water_mark))
    assert_bad_table(table)
  end

  define_test :largest_data_block_size_succeeds do
    table = Table.new(ThinPoolTarget.new(@size, @metadata_dev, @data_dev,
                                         2**21, @low_water_mark))
    with_dev(table) {|pool| {}}
  end

  define_test :too_large_a_dev_t_fails do
    with_standard_pool(@size) do |pool|
      assert_raises(ExitError) {pool.message(0, "create_thin #{2**24}")}
    end
  end

  define_test :largest_dev_t_succeeds do
    with_standard_pool(@size) {|pool| pool.message(0, "create_thin #{2**24 - 1}")}
  end

  define_test :too_small_a_metadata_dev_fails do
    tvm = VM.new
    tvm.add_allocation_volume(@data_dev)

    md_size = 32                # 16k, way too small
    data_size = 2097152
    tvm.add_volume(linear_vol('metadata', md_size))
    tvm.add_volume(linear_vol('data', 2097152))

    with_devs(tvm.table('metadata'),
              tvm.table('data')) do |md, data|
      wipe_device(md)
      assert_raise(ExitError) do
        with_dev(Table.new(ThinPoolTarget.new(data_size, md, data, 128, 1))) do |pool|
          # shouldn't get here
        end
      end
    end
  end

  # This is _not_ how linux behaves
  def _test_flush_on_close
    tvm = VM.new
    tvm.add_allocation_volume(@data_dev)

    data_size = 2097152
    tvm.add_volume(linear_vol('metadata', 4096))
    tvm.add_volume(linear_vol('data', data_size))

    with_devs(tvm.table('metadata'),
              tvm.table('data')) do |md, data|
      wipe_device(md)

      with_dev(Table.new(ThinPoolTarget.new(data_size, md, data, 128, 1))) do |pool|

        traces = nil

        with_new_thin(pool, @volume_size / 4, 0) do |thin|
          traces, _ = blktrace(thin) do
            wipe_device(thin)
          end
        end

        found_flush = false
        traces[0].each do |ev|
          if ev.code.member?(:sync)
            found_flush = true
          end
        end

        assert(found_flush)
      end
    end
  end
end

#----------------------------------------------------------------
