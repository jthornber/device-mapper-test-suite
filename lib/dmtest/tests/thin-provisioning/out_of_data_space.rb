require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/disk-units'
require 'dmtest/thinp-test'
require 'timeout'
require 'rspec/expectations'

#----------------------------------------------------------------

class OutOfDataSpaceTests < ThinpTestCase
  include Utils
  include DiskUnits
  extend TestUtils

  def setup
    super
    @low_water_mark = 0
    @data_block_size = 128

    wipe_device(@metadata_dev, 8)
  end

  #--------------------------------

  tag :thinp_target

  def zero_fill_thin_device(pool_size, thin_size, expected_error)
    with_standard_pool(pool_size, :error_if_no_space => true) do |pool|
      with_new_thin(pool, thin_size, 0) do |thin|
        begin
          block_size = meg(1)
          ProcessControl.run("dd if=/dev/zero of=#{thin} oflag=direct bs=#{block_size * 512}")
        rescue ExitError => e
          assert(e.error_code != 0)
          assert(/#{expected_error}/.match(e.stderr))
        end
      end
    end
  end

  define_test :filling_pool_returns_enospc do
    zero_fill_thin_device(@volume_size/2, @volume_size, "No space left on device")
  end

  define_test :filling_thin_device_returns_enospc do
    zero_fill_thin_device(@volume_size*10, @volume_size, "No space left on device")
  end

end
