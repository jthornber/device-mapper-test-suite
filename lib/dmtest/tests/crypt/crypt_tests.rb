require 'dmtest/config'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tests/cache/fio_subvolume_scenario'

require 'pp'

#----------------------------------------------------------------

class CryptStack
  include DiskUnits
  include ThinpTestMixin
  include Utils

  attr_accessor :crypt, :opts

  def initialize(dm, dev, opts)
    @dm = dm
    @device = dev

    @crypt = nil
    @opts = opts

    device_size = opts.fetch(:device_size, gig(1))

    @tvm = TinyVolumeManager::VM.new
    @tvm.add_allocation_volume(dev, 0, dev_size(dev))
    @tvm.add_volume(linear_vol('device', device_size))
  end

  def activate(&block)
    with_devs(@tvm.table('device')) do |device|
      key_file = LP("tests/crypt/crypt_keyfile") # FIXME: need unique name
      ProcessControl.run("dd if=/dev/urandom of=#{key_file} bs=1024 count=4")

      ProcessControl.run("cryptsetup luksFormat #{device} #{key_file}")
      crypt_name = "crypt1" # FIXME: need unqiue name
      ProcessControl.run("cryptsetup luksOpen --key-file #{key_file} #{device} #{crypt_name}")

      @crypt = "/dev/mapper/#{crypt_name}"
      block.call(@crypt)
      # FIXME: need to call this no matter whether the block fails...
      ProcessControl.run("cryptsetup luksClose #{crypt_name}")
    end
  end
end

#----------------------------------------------------------------

class CryptTests < ThinpTestCase
  include Utils
  include DiskUnits
  include FioSubVolumeScenario

  def test_basic_setup
    stack = CryptStack.new(@dm, @data_dev, {})
    stack.activate do |crypt|
      wipe_device(crypt)
    end
  end

  def test_fio_database_funtime
    stack = CryptStack.new(@dm, @data_dev, :device_size => gig(10))
    stack.activate do |crypt|
      do_fio(crypt, :xfs,
             :outfile => AP("fio_dm_crypt.out"),
             :cfgfile => LP("tests/cache/database-funtime.fio"))
    end
  end

  def _test_cpu_hotplug
    stack = CryptStack.new(@dm, @data_dev, :device_size => gig(2))
    stack.activate do |crypt|
      fork {dt_device(crypt, "sequential")}

      # FIXME: this test is useless at the moment.  need to offline cpu
      # that is known to be used for dm-crypt, use parallel IO generator?
      # But I even tried using a special kernel hack and that didn't enduce
      # crash so there is more work needed to categorize the cpu hotplug race.

      sleep 10
      # offline a cpu..
      ProcessControl.run("echo 0 > /sys/devices/system/cpu/cpu1/online")

      Process.wait
      if $?.exitstatus > 0
        ProcessControl.run("echo 1 > /sys/devices/system/cpu/cpu1/online")
        raise RuntimeError, "wipe sub process failed"
      else
        ProcessControl.run("echo 1 > /sys/devices/system/cpu/cpu1/online")
      end

    end
  end

end
