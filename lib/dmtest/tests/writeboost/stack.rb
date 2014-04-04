require 'dmtest/utils'
require 'dmtest/ensure_elapsed'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'
require 'dmtest/test-utils'

#----------------------------------------------------------------

module DM
  class WriteboostTarget < Target
    def initialize(sector_count, args)
      super('writeboost', sector_count, *args)
    end
    # writeboost doesn't need to implement post_remove_check
  end
end

#----------------------------------------------------------------

# template class for stacks
class WriteboostStack
  include EnsureElapsed
  include DiskUnits
  include ThinpTestMixin
  include Utils

  attr_accessor :backing_dev, # :: DMDev
                :cache_dev,
                :plog_dev, # not used now
                :wb,
                :opts # :: {}

  def initialize(dm, slow_dev_name, fast_dev_name, opts = {})
    @dm = dm
    @fast_dev_name = fast_dev_name
    @slow_dev_name = slow_dev_name

    @backing_dev = nil
    @cache_dev = nil
    @plog_dev = nil

    @opts = opts

    @fast_tvm = TinyVolumeManager::VM.new
    @fast_tvm.add_allocation_volume(fast_dev_name, 0, dev_size(fast_dev_name))
    @fast_tvm.add_volume(linear_vol('cache_dev', cache_sz))
    @fast_tvm.add_volume(linear_vol('plog_dev', plog_sz))

    @slow_tvm = TinyVolumeManager::VM.new
    @slow_tvm.add_allocation_volume(slow_dev_name, 0, dev_size(slow_dev_name))
    @slow_tvm.add_volume(linear_vol('backing_dev', backing_sz))
  end

  def backing_sz
    @opts.fetch(:backing_sz, dev_size(@slow_dev_name))
  end

  # cache_sz + plog_sz < 1GB
  def cache_sz
    @opts.fetch(:cache_sz, meg(989))
  end

  def plog_sz
    @opts.fetch(:plog_sz, meg(10))
  end

  def cleanup_cache
    # FIXME
    # @cache_dev.discard(0, dev_size(@cache_dev.path))
    wipe_device(@cache_dev, 1)
  end

  def activate_support_devs(&block)
    with_devs(@slow_tvm.table('backing_dev'),
              @fast_tvm.table('cache_dev'),
              @fast_tvm.table('plog_dev')
             ) do |backing_dev, cache_dev, plog_dev|
      @backing_dev = backing_dev
      @cache_dev = cache_dev
      @plog_dev = plog_dev

      ensure_elapsed_time(1, self, &block)
    end
  end

  def cleanup_forcibly
    @wb.suspend
    @wb.resume
  end

  def activate_top_level(force, &block)
    with_dev(table) do |wb|
      @wb = wb
      ensure_elapsed_time(1, self, &block)
      cleanup_forcibly if force
    end
  end

  def activate(force, &block)
    activate_support_devs do
      cleanup_cache
      activate_top_level(force, &block)
    end
  end

  class Args
    OPTIONALS = [:segment_size_order,
                 :nr_rambuf_pool,
    ]
    TUNABLES = [:barrier_deadline_ms,
                :allow_migrate,
                :enable_migration_modulator,
                :migrate_threshold,
                :nr_max_batched_migration,
                :update_record_interval,
                :sync_interval,
    ]
    def pop
      k,v = @opts.first
      if OPTIONALS.include? k
        @optionals[k] = v
        @opts.delete k
        return
      end
      if TUNABLES.include? k
        @tunables[k] = v
        @opts.delete k
        return
      end
    end
    def initialize(opts)
      @optionals = {}
      @tunables = {}

      @opts = opts.clone
      unless @opts.empty?
        @opts.pop
      end
    end
    # {k1=>v1, k2=>v2} -> [N k1 v1 k2 v2]
    def h_to_a(h)
      a = [h.size]
      h.each_with_index do |k, v|
        a += [k, v]
      end
      a
    end
    def to_a
      a = []
      a += h_to_a(@optionals) unless @optionals.empty?
      a += h_to_a(@tunables) unless @tunables.empty?
      a
    end
  end
end

class WriteboostStackType0 < WriteboostStack
  def table
    essentials = [0, @backing_dev, @cache_dev]
    args = Args.new(@opts)
    Table.new(WriteboostTarget.new(backing_sz, essentials + args.to_a))
  end
end

class WriteboostStackType1 < WriteboostStack
  def table
    essentials = [1, @backing_dev, @cache_dev, @plog_dev]
    args = Args.new(@opts)
    Table.new(WriteboostTarget.new(backing_sz, essentials + args.to_a))
  end
end
