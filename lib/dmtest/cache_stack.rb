require 'dmtest/utils'
require 'dmtest/ensure_elapsed'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'
require 'dmtest/test-utils'

#----------------------------------------------------------------

class CacheStack
  include EnsureElapsed
  include DiskUnits
  include ThinpTestMixin
  include Utils

  attr_accessor :tvm, :md, :ssd, :origin, :cache, :opts

  # options:
  #    :cache_size (in sectors),
  #    :block_size (in sectors),
  #    :policy (class Policy),
  #    :format (bool),
  #    :origin_size (sectors)

  
  # FIXME: writethrough/writeback
  # FIXME: add methods for changing the policy + args

  def initialize(dm, ssd_dev, spindle_dev, opts)
    @dm = dm
    @ssd_dev = ssd_dev
    @spindle_dev = spindle_dev

    @md = nil
    @ssd = nil
    @origin = nil
    @cache = nil
    @opts = opts

    @tvm = TinyVolumeManager::VM.new
    @tvm.add_allocation_volume(ssd_dev)
    @tvm.add_volume(linear_vol('md', metadata_size))
    @tvm.add_volume(linear_vol('ssd', cache_size == :all ? @tvm.free_space : cache_size))

    @data_tvm = TinyVolumeManager::VM.new
    @data_tvm.add_allocation_volume(spindle_dev)

    @data_tvm.add_volume(linear_vol('origin', origin_size == :all ? @data_tvm.free_space : origin_size))
  end

  def metadata_size
    opts.fetch(:metadata_size, meg(4))
  end

  def cache_size
    opts.fetch(:cache_size, gig(1))
  end

  def cache_blocks
    cache_size / block_size
  end

  def block_size
    opts.fetch(:block_size, k(32))
  end

  def activate_support_devs(&block)
    with_devs(@tvm.table('md'),
              @tvm.table('ssd'),
              @data_tvm.table('origin')) do |md, ssd, origin|
      @md = md
      @ssd = ssd
      @origin = origin

      wipe_device(md, 8) if @opts.fetch(:format, true)
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
    with_devs(@tvm.table('md'),
              @tvm.table('ssd'),
              @data_tvm.table('origin')) do |md, ssd, origin|
      @md = md
      @ssd = ssd
      @origin = origin

      wipe_device(md, 8) if @opts.fetch(:format, true)

      with_dev(cache_table) do |cache|
        @cache = cache
        ensure_elapsed_time(1, self, &block)
      end
    end
  end

  # load the origin into the cache dev, and load empty error targets into the
  # origin and ssd
  def uncache
    error_table = Table.new(ErrorTarget.new(1024))

    @cache.pause do
      @cache.load(@data_tvm.table('origin'))
      @origin.pause {@origin.load(error_table)}
      @ssd.pause {@ssd.load(error_table)}
    end
  end

  def resize_ssd(new_size)
    @cache.pause do        # must suspend cache so resize is detected
      @ssd.pause do
        @tvm.resize('ssd', new_size)
        @ssd.load(@tvm.table('ssd'))
      end
    end
  end

  def resize_origin(new_size)
    @opts[:data_size] = new_size

    @cache.pause do
      @origin.pause do
        @data_tvm.resize('origin', new_size)
        @origin.load(@data_tvm.table('origin'))
      end
      @cache.load(cache_table)
    end
  end

  def reload_cache
    @cache.load(cache_table)
  end

  def origin_size
    @opts.fetch(:data_size, dev_size(@spindle_dev))
  end

  def metadata_blocks
    @tvm.volumes['md'].length / 8
  end

  def policy
    @opts.fetch(:policy, Policy.new('default'))
  end

  def change_policy(new_policy)
    @opts[:policy] = new_policy
  end

  def io_mode
    @opts[:io_mode] ? [ @opts[:io_mode] ] : []
  end

  def metadata_version
    if @opts.has_key? :metadata_version
      case @opts[:metadata_version]
      when 1
        []
      when 2
        [:metadata2]
      else
        throw "bad metadata version"
      end
    else
      # We default to version 1
      []
    end
  end

  def change_io_mode(m)
    @opts[:io_mode] = m
  end

  def cache_table(mode = io_mode)
    Table.new(CacheTarget.new(dev_size(@origin), @md, @ssd, @origin,
                              block_size, mode + migration_threshold + metadata_version,
                              policy.name, policy.opts))
  end

  def with_io_mode(mode, &block)
    @cache.pause do
      @cache.load(cache_table([mode]))
    end

    block.call

    @cache.pause do
      @cache.load(cache_table)
    end
  end

  def wait_for_clean_cache
    cache.event_tracker.wait(cache) do |cache|
      status = CacheStatus.new(cache)
      status.nr_dirty == 0
    end
  end

  def prepare_populated_cache(overrides = Hash.new)
    raise "metadata device not active" if @md.nil?
    raise "cache target already active" unless @cache.nil?

    dirty_percentage = overrides.fetch(:dirty_percentage, 0)
    dirty_flag = "--dirty-percent #{dirty_percentage}"

    clean_shutdown = overrides.fetch(:clean_shutdown, true)
    omit_shutdown_flag = clean_shutdown ? '' : "--omit-clean-shutdown"
    metadata_version_flag = (metadata_version == [:metadata2]) ? "--metadata-version 2" : '--metadata-version 1'

    xml_file = 'metadata.xml'
    ProcessControl.run("cache_xml create --block-size #{block_size} --nr-cache-blocks #{cache_blocks} --nr-mappings #{cache_blocks} #{dirty_flag} > #{xml_file}")
    ProcessControl.run("cache_restore #{omit_shutdown_flag} #{metadata_version_flag} -i #{xml_file} -o #{@md}")
  end

  private
  def migration_threshold
    @opts[:migration_threshold] ? [ "migration_threshold", opts[:migration_threshold].to_s ] : []
  end
end

#----------------------------------------------------------------
