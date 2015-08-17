require 'dmtest/config'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tests/cache/fio_subvolume_scenario'

require 'pp'

#----------------------------------------------------------------

class EnhanceIOStack
  include DiskUnits
  include ThinpTestMixin
  include Utils

  attr_accessor :ssd, :cache, :opts

  def initialize(dm, ssd_dev, spindle_dev, opts)
    @dm = dm
    @ssd_dev = ssd_dev
    @spindle_dev = spindle_dev

    @cache = nil
    @opts = opts

    @tvm = TinyVolumeManager::VM.new
    @tvm.add_allocation_volume(ssd_dev)
    @tvm.add_volume(linear_vol('md', meg(4)))

    cache_size = opts.fetch(:cache_size, gig(1))
    @tvm.add_volume(linear_vol('ssd', cache_size))

    @data_tvm = TinyVolumeManager::VM.new
    @data_tvm.add_allocation_volume(spindle_dev)
    @data_tvm.add_volume(linear_vol('origin', origin_size))
  end

  def activate(&block)
    with_devs(@tvm.table('ssd'),
              @data_tvm.table('origin')) do |ssd, origin|
      @cache = origin
      ProcessControl.run("eio_cli create -d #{origin} -s #{ssd} -p #{policy} -m #{cache_mode} -b #{block_size} -c #{cache_name}")
      block.call(@cache)
      ProcessControl.run("eio_cli delete -c #{cache_name}")
    end
  end

  def policy
    @opts.fetch(:policy, 'fifo')
  end

  def cache_mode
    @opts.fetch(:cache_mode, 'wb')
  end

  def block_size
    @opts.fetch(:block_size, 4096)
  end

  def cache_name
    @opts.fetch(:cache_name, "eio_cache1")
  end

  def origin_size
    @opts.fetch(:data_size, dev_size(@spindle_dev))
  end
end

#----------------------------------------------------------------

class EnhanceIOTests < ThinpTestCase
  include GitExtract
  include Utils
  include DiskUnits
  include FioSubVolumeScenario
  extend TestUtils

  #--------------------------------

  define_test :fio_sub_volume do
    stack = EnhanceIOStack.new(@dm, @metadata_dev, @data_dev, :cache_size => meg(256))
    stack.activate do |cache|
      wait = lambda {sleep(5)}
      fio_sub_volume_scenario(cache, &wait)
    end
  end
end

#----------------------------------------------------------------
