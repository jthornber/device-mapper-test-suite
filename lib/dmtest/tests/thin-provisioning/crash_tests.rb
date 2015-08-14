require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/disk-units'
require 'dmtest/thinp-test'
require 'dmtest/test-utils'
require 'timeout'
require 'rspec/expectations'

#----------------------------------------------------------------

class CrashTests < ThinpTestCase
  include Tags
  include Utils
  include TinyVolumeManager
  extend TestUtils

  def setup
    super
    @low_water_mark = 0
    @data_block_size = 128
  end

  #--------------------------------

  tag :thinp_target

  # In all these tests we're interested in whether the thin_check that
  # runs when the pool is taken down, passes.
  define_test :aborting_a_fresh_pool do
    with_standard_pool(@size) do |pool|
      pool.message(0, "set_mode read-only abort")
    end
  end

  define_test :aborting_a_provisioned_thin do
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)

        pool.message(0, "set_mode read-only abort");
      end
    end
  end

  define_test :aborting_during_io do
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) do |thin|
        tid = Thread.new(thin) do |thin|
          # we're expecting this to fail
          failed = false
          begin
            wipe_device(thin)
          rescue
            failed = true
          end

          failed.should be_true
        end

        sleep 2
        pool.message(0, "set_mode read-only abort");

        tid.join()
      end
    end
  end
end

#----------------------------------------------------------------
