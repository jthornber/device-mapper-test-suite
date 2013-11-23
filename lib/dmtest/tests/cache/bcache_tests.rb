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

class BcacheStack
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
    @tvm.add_allocation_volume(ssd_dev, 0, dev_size(ssd_dev))
    @tvm.add_volume(linear_vol('md', meg(4)))

    cache_size = opts.fetch(:cache_size, gig(1))
    @tvm.add_volume(linear_vol('ssd', cache_size))

    @data_tvm = TinyVolumeManager::VM.new
    @data_tvm.add_allocation_volume(spindle_dev, 0, dev_size(spindle_dev))
    @data_tvm.add_volume(linear_vol('origin', origin_size))
  end

  def activate(&block)
    with_devs(@tvm.table('ssd'),
              @data_tvm.table('origin')) do |ssd, origin|
      bucket_size = block_size / 2
      ProcessControl.run("make-bcache  --cache_replacement_policy=#{policy} -b #{bucket_size}k --writeback --discard -B #{origin} -C #{ssd}")
      ProcessControl.run("echo #{origin} > /sys/fs/bcache/register")
      ProcessControl.run("echo #{ssd} > /sys/fs/bcache/register")

      # need to readlink to get the bcache device name... so nasty
      # ls -ltr /sys/block/dm-10/bcache/dev
      # lrwxrwxrwx 1 root root 0 Jan 16 13:58 /sys/block/dm-10/bcache/dev -> ../../bcache3
      bcache_name = File.readlink("/sys/block/#{origin.dm_name}/bcache/dev").split('/')[2]
      @cache = "/dev/#{bcache_name}"
      block.call(@cache)
      ProcessControl.run("echo 1 > /sys/block/#{bcache_name}/bcache/cache/unregister")
      ProcessControl.run("echo 1 > /sys/block/#{bcache_name}/bcache/stop")
    end
  end

  def policy
    @opts.fetch(:policy, 'lru')
  end

  def cache_mode
    @opts.fetch(:cache_mode, 'wb')
  end

  def block_size
    @opts.fetch(:block_size, 1024)
  end

  def origin_size
    @opts.fetch(:data_size, dev_size(@spindle_dev))
  end
end

#----------------------------------------------------------------

class BcacheTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  include FioSubVolumeScenario
  extend TestUtils

  #--------------------------------

  def test_git_extract_quick
    stack = BcacheStack.new(@dm, @metadata_dev, @data_dev, :cache_size => meg(256))
    stack.activate do |cache|
      git_prepare(cache, :ext4)
      git_extract(cache, :ext4, TAGS[0..5])
    end
  end

  def test_fio_sub_volume
    stack = BcacheStack.new(@dm, @metadata_dev, @data_dev,
                            :cache_size => meg(256),
                            :format => true,
                            :block_size => 1024,
                            :data_size => gig(4))
    stack.activate do |cache|
      wait = lambda {sleep(5)}
      fio_sub_volume_scenario(cache, &wait)
    end
  end

  def test_fio_database_funtime
    stack = BcacheStack.new(@dm, @metadata_dev, @data_dev,
                            :cache_size => meg(1024),
                            :format => true,
                            :block_size => 256,
                            :data_size => gig(10))
    stack.activate do |cache|
      do_fio(cache, :ext4,
             :outfile => AP("fio_bcache.out"),
             :cfgfile => LP("tests/cache/database-funtime.fio"))
    end
  end

end

#----------------------------------------------------------------
