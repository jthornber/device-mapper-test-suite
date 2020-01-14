require 'dmtest/utils'
require 'dmtest/ensure_elapsed'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'
require 'dmtest/test-utils'

#----------------------------------------------------------------

class WriteCacheStack
  include EnsureElapsed
  include DiskUnits
  include ThinpTestMixin
  include Utils

  attr_accessor :tvm, :ssd, :origin, :cache, :opts

  # options:
  #    :cache_size (in sectors),
  #    :data_size (in sectors),
  #    :format (bool),

  def initialize(dm, ssd_dev, spindle_dev, opts)
    @dm = dm
    @ssd_dev = ssd_dev
    @spindle_dev = spindle_dev

    @ssd = nil
    @origin = nil
    @cache = nil
    @opts = opts

    @tvm = TinyVolumeManager::VM.new
    @tvm.add_allocation_volume(ssd_dev)
    @tvm.add_volume(linear_vol('ssd', cache_size == :all ? @tvm.free_space : cache_size))

    @data_tvm = TinyVolumeManager::VM.new
    @data_tvm.add_allocation_volume(spindle_dev)

    @data_tvm.add_volume(linear_vol('origin', origin_size == :all ? @data_tvm.free_space : origin_size))
  end

  def block_size
    4096
  end

  def cache_size
    opts.fetch(:cache_size, gig(1))
  end

  def cache_blocks
    cache_size / block_size
  end

  def activate_support_devs(&block)
    with_devs(@tvm.table('ssd'),
              @data_tvm.table('origin')) do |ssd, origin|
      @ssd = ssd
      @origin = origin

      wipe_device(ssd, 8) if @opts.fetch(:format, true)
      ensure_elapsed_time(1, self, &block)
    end
  end

  def activate_top_level(&block)
    with_dev(cache_table) do |cache|
      @cache = cache
      ensure_elapsed_time(1, self, &block)
    end
  end

  def activate(&block)
    with_devs(@tvm.table('ssd'),
              @data_tvm.table('origin')) do |ssd, origin|
      @ssd = ssd
      @origin = origin

      wipe_device(ssd, 8) if @opts.fetch(:format, true)

      with_dev(cache_table) do |cache|
        @cache = cache
        ensure_elapsed_time(1, self, &block)
      end
    end
  end

  def origin_size
    @opts.fetch(:data_size, dev_size(@spindle_dev))
  end

  def cache_table()
    Table.new(WriteCacheTarget.new(dev_size(@origin), @ssd, @origin, block_size))
  end
end

#----------------------------------------------------------------
