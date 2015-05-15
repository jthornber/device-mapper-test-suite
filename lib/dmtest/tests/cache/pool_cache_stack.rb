require 'dmtest/ensure_elapsed'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/cache_policy'

require 'rspec/expectations'

#----------------------------------------------------------------

class PoolCacheStack
  include DiskUnits
  include DM
  include DM::LexicalOperators
  include EnsureElapsed
  include Utils
  include TinyVolumeManager;

  attr_reader :dm, :cache

  def initialize(dm, ssd_dev, spindle_dev, cache_opts, pool_opts)
    @dm, @ssd_dev, @spindle_dev, @cache_opts, @pool_opts = [dm, ssd_dev, spindle_dev, cache_opts, pool_opts]

    @ssd_tvm = TinyVolumeManager::VM.new
    @ssd_tvm.add_allocation_volume(@ssd_dev)
    @ssd_tvm.add_volume(linear_vol('pool_md', meg(64)))
    @ssd_tvm.add_volume(linear_vol('cache_ssd', meg(64) + @cache_opts.fetch(:cache_size, meg(256))))
  end

  def activate(&block)
    with_devs(@ssd_tvm.table('cache_ssd'),
              @ssd_tvm.table('pool_md')) do |cache_ssd, pool_md|
      cache_stack = CacheStack.new(@dm, cache_ssd, @spindle_dev, @cache_opts)
      cache_stack.activate do |cs|
        @cache = cs.cache
        cs.cache.discard(0, dev_size(cs.cache))
        pool_stack = PoolStack.new(@dm, cs.cache, pool_md, @pool_opts)
        pool_stack.activate(&block)
      end
    end
  end

  private
  def dm_interface
    @dm
  end
end

#----------------------------------------------------------------
