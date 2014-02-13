require 'dmtest/device-mapper/lexical_operators'
require 'dmtest/device-mapper/table'
require 'dmtest/disk-units'
require 'dmtest/ensure_elapsed'
require 'dmtest/era_status'
require 'dmtest/tvm'
require 'dmtest/utils'

#----------------------------------------------------------------

class EraStack
  include DM
  include DM::LexicalOperators
  include DiskUnits
  include EnsureElapsed
  include Utils
  include TinyVolumeManager

  attr_accessor :metadata_pv, :data_pv, :md, :origin, :era, :opts

  # opts:
  #    :metadata_size (sectors)
  #    :origin_size (sectors)
  #    :block_size (sectors)
  #    :format (bool)
  def initialize(dm, metadata_pv, origin_pv, opts)
    @dm = dm
    @metadata_pv = metadata_pv
    @origin_pv = origin_pv
    @opts = opts

    @metadata_tvm = TinyVolumeManager::VM.new
    @metadata_tvm.add_allocation_volume(@metadata_pv, 0, dev_size(@metadata_pv))
    @metadata_tvm.add_volume(linear_vol('md', metadata_size))

    @origin_tvm = TinyVolumeManager::VM.new
    @origin_tvm.add_allocation_volume(@origin_pv, 0, dev_size(@origin_pv))
    @origin_tvm.add_volume(linear_vol('origin', origin_size))
  end

  def metadata_size
    @opts.fetch(:metadata_size, meg(4))
  end

  def origin_size
    @opts.fetch(:origin_size, gig(1))
  end

  def block_size
    @opts.fetch(:block_size, k(64))
  end

  def era_table
    Table.new(EraTarget.new(origin_size, @md, @origin, block_size))
  end

  def activate_support_devs(&block)
    with_devs(@metadata_tvm.table('md'),
              @origin_tvm.table('origin')) do |md, origin|
      @md = md
      @origin = origin
      wipe_device(md, 8) if @opts.fetch(:format, true)
      ensure_elapsed_time(1, self, &block)
    end
  end

  def activate_top_level(&block)
    with_dev(era_table) do |era|
      @era = era
      ensure_elapsed_time(1, self, &block)
    end
  end

  def activate(&block)
    activate_support_devs do
      activate_top_level(&block)
    end
  end

  def checkpoint
    @era.message(0, "checkpoint")
    status = EraStatus.new(@era)
    status.current_era
  end

  def dm_interface
    @dm
  end
end

#----------------------------------------------------------------
