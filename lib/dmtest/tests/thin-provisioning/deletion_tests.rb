require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/status'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

class DeletionTests < ThinpTestCase
  include Tags
  include Utils

  def setup
    super
    @max=1000
  end

  tag :thinp_target, :create_delete

  def test_create_delete_cycle
    with_standard_pool(@size) do |pool|
      @max.times do
        pool.message(0, "create_thin 0")
        pool.message(0, "delete 0")
      end
    end
  end

  def test_create_many_thins_then_delete_them
    with_standard_pool(@size) do |pool|
      0.upto(@max) {|id| pool.message(0, "create_thin #{id}")}
      0.upto(@max) {|id| pool.message(0, "delete #{id}")}
    end
  end

  def test_rolling_create_delete
    with_standard_pool(@size) do |pool|
      0.upto(@max) {|id| pool.message(0, "create_thin #{id}")}
      0.upto(@max) do |id|
        pool.message(0, "delete #{id}")
        pool.message(0, "create_thin #{id}")
      end
    end
  end

  def test_delete_thin
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @tiny_size, 0) {|thin| wipe_device(thin)}
      assert_equal(@tiny_size, 
                   PoolStatus.new(pool).used_data_blocks * @data_block_size)

      pool.message(0, 'delete 0')
      assert_equal(0, PoolStatus.new(pool).used_data_blocks)
    end
  end

  tag :thinp_target, :quick

  def test_delete_unknown_devices
    with_standard_pool(@size) do |pool|
      0.upto(10) do |id|
        assert_raise(ExitError) {pool.message(0, "delete #{id}")}
      end
    end
  end

  def test_delete_active_device_fails
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @size, 0) do |thin|
        assert_raise(ExitError) {pool.message(0, 'delete 0')}
      end
    end
  end
end

#----------------------------------------------------------------
