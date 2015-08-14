require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/status'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/test-utils'

#----------------------------------------------------------------

class DeletionTests < ThinpTestCase
  include Tags
  include Utils
  extend TestUtils

  def setup
    super
    @max=1000
  end

  tag :thinp_target, :create_delete

  define_test :create_delete_cycle do
    with_standard_pool(@size) do |pool|
      @max.times do
        pool.message(0, "create_thin 0")
        pool.message(0, "delete 0")
      end
    end
  end

  define_test :create_many_thins_then_delete_them do
    with_standard_pool(@size) do |pool|
      0.upto(@max) {|id| pool.message(0, "create_thin #{id}")}
      0.upto(@max) {|id| pool.message(0, "delete #{id}")}
    end
  end

  define_test :rolling_create_delete do
    with_standard_pool(@size) do |pool|
      0.upto(@max) {|id| pool.message(0, "create_thin #{id}")}
      0.upto(@max) do |id|
        pool.message(0, "delete #{id}")
        pool.message(0, "create_thin #{id}")
      end
    end
  end

  define_test :delete_thin do
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @tiny_size, 0) {|thin| wipe_device(thin)}
      assert_equal(@tiny_size, 
                   PoolStatus.new(pool).used_data_blocks * @data_block_size)

      pool.message(0, 'delete 0')
      assert_equal(0, PoolStatus.new(pool).used_data_blocks)
    end
  end

  tag :thinp_target, :quick

  define_test :delete_unknown_devices do
    with_standard_pool(@size) do |pool|
      0.upto(10) do |id|
        assert_raise(ExitError) {pool.message(0, "delete #{id}")}
      end
    end
  end

  define_test :delete_active_device_fails do
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @size, 0) do |thin|
        assert_raise(ExitError) {pool.message(0, 'delete 0')}
      end
    end
  end

  define_test :delete_after_out_of_space do
    with_standard_pool(@size, :error_if_no_space => true) do |pool|
      with_new_thin(pool, @size * 2, 0) do |thin|
        begin
          wipe_device(thin)
        rescue
        end

        s = PoolStatus.new(pool)
        s.options[:mode].should == :out_of_data_space
      end

      pool.message(0, 'delete 0')

      s = PoolStatus.new(pool)
      s.used_data_blocks.should == 0
      s.options[:mode].should == :read_write
    end
  end
end

#----------------------------------------------------------------
