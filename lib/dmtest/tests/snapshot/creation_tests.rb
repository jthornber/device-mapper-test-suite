require 'dmtest/utils'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/thinp-test'
require 'dmtest/snapshot_utils'
require 'dmtest/snapshot_stack'

require 'rspec/expectations'

#----------------------------------------------------------------

class CreationTests < ThinpTestCase
  include Utils
  include DiskUnits
  include SnapshotUtils
  extend TestUtils

  PERSISTENT = [:P, :N]

  def setup
    super
    @max=100
    @chunk_size = k(4)
  end

  def bring_up_snapshot_target(persistent)
    s = SnapshotStack.new(@dm, @data_dev, :origin_size => @volume_size)
    s.activate do
      s.with_new_snap(0, meg(1), persistent, @chunk_size) do
      end
    end
  end

  define_tests_across(:bring_up_snapshot_target, PERSISTENT)

  def create_lots_of_snaps(persistent)
    s = SnapshotStack.new(@dm, @data_dev, :origin_size => @volume_size)
    s.activate do
      s.with_new_snaps(meg(1), persistent, @chunk_size, *(0..@max)) {}
    end
  end

  define_tests_across(:create_lots_of_snaps, PERSISTENT)

  def huge_chunk_size(persistent)
    chunk_size = 524288
    snapshot_size = max_snapshot_size(chunk_size, chunk_size, persistent)

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => chunk_size)
    s.activate do
      s.with_new_snap(0, snapshot_size, persistent, chunk_size) do
        dt_device(s.origin)
      end
    end
  end

  define_tests_across(:huge_chunk_size, PERSISTENT)

  define_test :non_power_of_2_chunk_size_fails do
    failed = false
    s = SnapshotStack.new(@dm, @data_dev, :origin_size => @volume_size)
    s.activate do
      begin
        s.with_new_snap(0, meg(1), :P, @chunk_size + 57) do
          # expect failure
        end
      rescue
        failed = true
      end
    end
    failed.should be_true
  end

  define_test :too_large_chunk_size_fails do
    chunk_size = 2 ** 22
    volume_size = chunk_size
    snapshot_size = max_snapshot_size(volume_size, chunk_size, :P)

    failed = false
    s = SnapshotStack.new(@dm, @data_dev, :origin_size => volume_size)
    s.activate do
      begin
        s.with_new_snap(0, snapshot_size, :P, chunk_size) do
          # expect failure
        end
      rescue
        failed = true
      end
    end
    failed.should be_true
  end

  def largest_chunk_size_succeeds(persistent)
    chunk_size = 2 ** 21
    volume_size = chunk_size
    snapshot_size = max_snapshot_size(volume_size, chunk_size, persistent)

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => volume_size)
    s.activate do
        s.with_new_snap(0, snapshot_size, persistent, chunk_size) {}
    end
  end

  define_tests_across(:largest_chunk_size_succeeds, PERSISTENT)
end

#----------------------------------------------------------------
