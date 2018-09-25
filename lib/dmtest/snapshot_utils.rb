require 'dmtest/math-utils'

#----------------------------------------------------------------

module SnapshotUtils
  include MathUtils

  SNAPSHOT_DISK_EXCEPTION_SIZE = 16

  def max_snapshot_size(origin_size, chunk_size, persistent=:P)
    if not is_power_of_2?(chunk_size)
      raise "Chunk size #{chunk_size} not a power of 2"
    end

    nr_chunks = div_up(origin_size, chunk_size)

    return nr_chunks * chunk_size if persistent == :N

    exceptions_per_area = (chunk_size * 512) / SNAPSHOT_DISK_EXCEPTION_SIZE

    # Take into account the dummy exception used to mark the end of the
    # exception store
    nr_areas = div_up(nr_chunks + 1, exceptions_per_area)

    # Header + space for metadata areas + space for data chunks
    chunk_size + (nr_areas + nr_chunks) * chunk_size
  end
end

#----------------------------------------------------------------
