require 'dmtest/utils'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'
require 'dmtest/test-utils'

#----------------------------------------------------------------

module DM
  class WriteboostTarget < Target
    def initialize(sector_count, cache_dev, origin_dev)
      args = [0, origin_dev, cache_dev]
      super('writeboost', sector_count, *args)
    end

    # writeboost doesn't need to implement post_remove_check
  end
end

#----------------------------------------------------------------

class WriteboostStack
  include DiskUnits
  include ThinpTestMixin
  include Utils

  attr_accessor :ssd, :origin, :cache, :opts

  def initialize(dm, ssd_dev, spindle_dev, opts)
    @dm = dm
    @ssd_dev = ssd_dev
    @spindle_dev = spindle_dev

    @ssd = nil
    @origin = nil
    @cache = nil
    @opts = opts

    @tvm = TinyVolumeManager::VM.new
    @tvm.add_allocation_volume(ssd_dev, 0, dev_size(ssd_dev))
    @tvm.add_volume(linear_vol('ssd', cache_size))

    @data_tvm = TinyVolumeManager::VM.new
    @data_tvm.add_allocation_volume(spindle_dev, 0, dev_size(spindle_dev))
    @data_tvm.add_volume(linear_vol('origin', origin_size))
  end

  def activate(&block)
    with_devs(@tvm.table('ssd'),
              @data_tvm.table('origin')) do |ssd, origin|

      @ssd = ssd
      @origin = origin

      wipe_device(ssd, 1) if @opts.fetch(:format, true)

      with_dev(cache_table) do |cache|
        @cache = cache
        ensure_elapsed_time(1, self, &block)
      end
    end
  end

  # FIXME copied from cache_stack
  # move to prelude?
  def ensure_elapsed_time(seconds, *args, &block)
    t = Thread.new(seconds) do |seconds|
      sleep seconds
    end

    block.call(*args)

    t.join
  end

  # not used yet
  def type
    @opts.fetch(:type, 0)
  end

  def cache_size
    @opts.fetch(:cache_size, meg(3))
  end

  def origin_size
    @opts.fetch(:data_size, dev_size(@spindle_dev))
  end

  def cache_table
    Table.new(WriteboostTarget.new(origin_size, @ssd, @origin))
  end
end

#----------------------------------------------------------------
