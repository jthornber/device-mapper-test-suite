require 'dmtest/disk-units'
require 'dmtest/thinp-test'
require 'dmtest/snapshot_utils'
require 'dmtest/snapshot_stack'
require 'dmtest/pattern_stomper'

#----------------------------------------------------------------

class ConsistencyTests < ThinpTestCase
  include DiskUnits
  include SnapshotUtils
  extend TestUtils

  PERSISTENT = [:P, :N]

  def setup
    super

    @chunk_size = k(4)
  end

  def snapshot_writes_do_not_affect_origin(persistent)
    snapshot_size = max_snapshot_size(@volume_size, @chunk_size, persistent)

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => @volume_size)
    s.activate do
      origin_stomper = PatternStomper.new(s.origin.path, @chunk_size)
      origin_stomper.stamp(20)

      s.with_new_snap(0, snapshot_size, persistent, @chunk_size) do |snap|
        snap_stomper = origin_stomper.fork(snap.path)
        snap_stomper.verify(0, 1)

        snap_stomper.stamp(10)
        snap_stomper.verify(0, 2)

        origin_stomper.verify(0, 1)
      end
    end
  end

  define_tests_across(:snapshot_writes_do_not_affect_origin, PERSISTENT)

  def origin_writes_do_not_affect_snapshot(persistent)
    snapshot_size = max_snapshot_size(@volume_size, @chunk_size, persistent)

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => @volume_size)
    s.activate do
      origin_stomper = PatternStomper.new(s.origin.path, @chunk_size)
      origin_stomper.stamp(20)

      s.with_new_snap(0, snapshot_size, persistent, @chunk_size) do |snap|
        snap_stomper = origin_stomper.fork(snap.path)

        origin_stomper.stamp(10)
        origin_stomper.verify(0, 2)

        snap_stomper.verify(0, 1)
      end
    end
  end

  define_tests_across(:origin_writes_do_not_affect_snapshot, PERSISTENT)
end

#----------------------------------------------------------------
