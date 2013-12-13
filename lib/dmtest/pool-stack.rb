#----------------------------------------------------------------

class PoolStack
  include DM
  include DM::LexicalOperators
  include Utils

  attr_reader :dm, :data_dev, :metadata_dev, :opts

  def initialize(dm, data_dev, metadata_dev, opts = {})
    @dm, @data_dev, @metadata_dev, @opts = [dm, data_dev, metadata_dev, opts]
  end

  def pool_table
    size = @opts.fetch(:data_size, dev_size(@data_dev))
    zero = @opts.fetch(:zero, true)
    discard = @opts.fetch(:discard, true)
    discard_pass = @opts.fetch(:discard_passdown, true)
    read_only = @opts.fetch(:read_only, false)
    error_if_no_space = @opts.fetch(:error_if_no_space, false)
    block_size = @opts.fetch(:block_size, 128)
    low_water_mark = @opts.fetch(:low_water_mark, 0)

    Table.new(ThinPoolTarget.new(size, @metadata_dev, @data_dev,
                                 block_size, low_water_mark,
                                 zero, discard, discard_pass, read_only,
                                 error_if_no_space))
  end

  def activate(&block)
    with_dev(pool_table) do |pool|
      @pool = pool
      block.call(pool)
    end
  end

  # FIXME: we should make this a separate stack
  def activate_thin(opts = Hash.new, &block)
    id = opts.fetch(:id, 0)
    create = opts.fetch(:create, false)

    if (create)
      @pool.message(0, "create_thin #{id}")
    end

    thin_table = Table.new(ThinTarget.new(opts[:thin], @pool, id, opts[:origin]))
    with_dev(thin_table, &block)
  end

  private
  def dm_interface
    @dm
  end
end

#------------------------------------------------

module DMThinUtils
  include DM
  include DM::LexicalOperators

  def thin_table(pool, size, id, opts = Hash.new)
    Table.new(ThinTarget.new(size, pool, id, opts[:origin]))
  end

  def with_thin(pool, size, id, opts = Hash.new, &block)
    with_dev(thin_table(pool, size, id, opts), &block)
  end

  def with_new_thin(pool, size, id, opts = Hash.new, &block)
    pool.message(0, "create_thin #{id}")
    with_thin(pool, size, id, opts, &block)
  end

  def with_thins(pool, size, *ids, &block)
    tables = ids.map {|id| thin_table(pool, size, id)}
    with_devs(*tables, &block)
  end

  def with_new_thins(pool, size, *ids, &block)
    ids.each do |id|
      pool.message(0, "create_thin #{id}")
    end

    with_thins(pool, size, *ids, &block)
  end

  private
  def dm_interface
    @dm
  end
end

#----------------------------------------------------------------
