require 'dmtest/tvm'
require 'dmtest/utils'
require 'dmtest/disk-units'
require 'dmtest/ensure_elapsed'
require 'dmtest/device-mapper/table'
require 'dmtest/device-mapper/lexical_operators'

#----------------------------------------------------------------

class SnapshotStack
  include DM
  include Utils
  include DiskUnits
  include EnsureElapsed
  include TinyVolumeManager
  include DM::LexicalOperators

  attr_reader :data_dev, :opts, :origin

  # opts:
  #    :origin_size (sectors)
  def initialize(dm, data_dev, opts = {})
    @dm = dm
    @data_dev = data_dev
    @opts = opts

    @tvm = TinyVolumeManager::VM.new
    @tvm.add_allocation_volume(@data_dev)
    @tvm.add_volume(linear_vol('origin-real', origin_size))

    @snaps = {}
  end

  def origin_size
    @opts.fetch(:origin_size, gig(1))
  end

  def snapshot_origin_table
    Table.new(SnapshotOriginTarget.new(origin_size, @origin_real))
  end

  def snapshot_table(cow_dev, persistent, chunk_size)
    Table.new(SnapshotTarget.new(origin_size, @origin_real, cow_dev, persistent,
                                 chunk_size))
  end

  def origin_real_table
    @tvm.table('origin-real')
  end

  def activate(&block)
    with_dev(origin_real_table) do |origin_real|
      @origin_real = origin_real
      with_dev(origin_real_table) do |origin|
        @origin = origin
        ensure_elapsed_time(1, self, &block)
      end
    end
  end

  def take_snap(id, snapshot_size, persistent=:P, chunk_size=k(4))
    if @snaps.include?(id)
      raise "Snapshot with id #{id} already exists."
    end

    @tvm.add_volume(linear_vol(id, snapshot_size))

    cow_dev, snap_dev = protect(id, @tvm.method(:remove_volume)) do |sid|
      cow_dev = create_dev(@tvm.table(sid))

      protect_(cow_dev.method(:remove)) do
        wipe_device(cow_dev, chunk_size)

        @origin.pause do
          snap_dev = create_dev(snapshot_table(cow_dev, persistent, chunk_size))
          @origin.load(snapshot_origin_table) if @snaps.empty?
          [cow_dev, snap_dev]
        end
      end
    end

    @snaps[id] = {:snap_dev => snap_dev, :cow_dev => cow_dev,
                  :persistent =>  persistent, :chunk_size => chunk_size}

    snap_dev
  end

  def drop_snap(id)
    snap = @snaps.fetch(id)
    snap_dev = snap[:snap_dev]
    cow_dev = snap[:cow_dev]

    @origin.pause do
      snap_dev.remove
      @snaps.delete(id)
      @origin.load(origin_real_table) if @snaps.empty?
    end

    cow_dev.remove
    @tvm.remove_volume(id)
  end

  def with_new_snap(id, snapshot_size, persistent=:P, chunk_size=k(4), &block)
    snap_dev = take_snap(id, snapshot_size, persistent, chunk_size)

    bracket(id, method(:drop_snap)) do |sid|
      ensure_elapsed_time(1, snap_dev, &block)
    end
  end

  def with_new_snaps(snapshot_size, persistent, chunk_size, *ids, &block)
    snaps = []
    sids = []

    cleanup = lambda {sids.each {|id| drop_snap(id)}}

    bracket_(cleanup) do
      ids.each do |id|
        snaps << take_snap(id, snapshot_size, persistent, chunk_size)
        sids << id
      end

      ensure_elapsed_time(1, *snaps, &block)
    end
  end

  def dm_interface
    @dm
  end
end

#----------------------------------------------------------------
