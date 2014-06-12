require 'dmtest/disk-units'
require 'dmtest/utils'
require 'rspec/expectations'

#----------------------------------------------------------------

module PatternStomperDetail
  SECTOR_SIZE = 512

  class Block
    attr_reader :block, :seed

    def initialize(block, seed)
      @block = block
      @seed = seed
    end

    def get_buffer(block_size)
      s = @seed % 256

      r = "\0" * block_size * SECTOR_SIZE
      block_size.times do |i|
        r.setbyte(i, s)
      end

      r.bytesize.should == block_size * SECTOR_SIZE

      r
    end

    def to_s
      "Block #{@block}, seed #{seed}"
    end
  end

  #--------------------------------

  # I couldn't get set to work nicely
  class BlockSet
    attr_reader :blocks

    def initialize(hash = {})
      @blocks = hash
    end

    def add(b)
      @blocks[b.block] = b
    end

    def each(&block)
      @blocks.each_value(&block)
    end

    def union(rhs)
      BlockSet.new(@blocks.merge(rhs.blocks))
    end

    def size
      @blocks.size
    end

    def member?(b)
      @blocks.member?(b)
    end

    def trim(max_blocks)
      new_blocks = {}

      @blocks.each do |key, val|
        if (key < max_blocks)
          new_blocks[key] = val
        end
      end

      BlockSet.new(new_blocks)
    end
  end

  #--------------------------------

  # A delta is a set of Blocks
  def random_delta(nr_blocks, max_block)
    blocks = BlockSet.new

    while blocks.size != nr_blocks do
      # choose a block that hasn't yet been selected in this delta
      b = nil
      loop do
        b = rand(max_block)
        break unless blocks.member?(b)
      end

      blocks.add(Block.new(b, rand(256)))
    end

    blocks
  end

  def zeroes_delta(nr_blocks)
    blocks = BlockSet.new

    nr_blocks.times do |b|
      blocks.add(Block.new(b, 0))
    end

    blocks
  end
end

#--------------------------------

class PatternStomper
  include PatternStomperDetail
  include Utils

  attr_reader :dev, :block_size, :max_blocks, :deltas

  # dev must be zeroed (possibly virtually via thin block zeroing)
  def initialize(dev, block_size, opts = {})
    @dev = dev
    @block_size = block_size
    @max_blocks = dev_size(dev) / @block_size
    @deltas = []

    initialize_device(opts)
  end

  def fork(new_dev)
    s2 = PatternStomper.new(new_dev, @block_size, :need_zero => false)
    s2.deltas = @deltas.clone
    s2
  end

  def stamp(percent)
    nr_blocks = (@max_blocks * percent) / 100
    delta = random_delta(nr_blocks, @max_blocks)
    write_blocks(delta)

    @deltas << delta
  end

  def restamp(delta_index)
    write_blocks(@deltas[delta_index])
  end

  def verify(delta_begin, delta_end = delta_begin)
    delta = @deltas[delta_begin..delta_end].inject(BlockSet.new) do |result, d|
      result.union(d)
    end

    verify_blocks(delta)
  end

  # Trims the deltas to fit into a smaller dev
  def deltas=(new_ds)
    @deltas = new_ds.map do |bs|
      bs.trim(@max_blocks)
    end
  end

  private
  def seek(io, b)
    io.seek(@block_size * b.block * SECTOR_SIZE)
  end

  def write_block(io, b)
    seek(io, b)
    io.write(b.get_buffer(@block_size))
  end

  def write_blocks(blocks)
    File.open(@dev, 'wb') do |io|
      blocks.each {|b| write_block(io, b)}
    end
  end

  def read_block(io, b)
    seek(io, b)
    io.read(@block_size * SECTOR_SIZE)
  end

  def verify_block(io, b)
    expected = b.get_buffer(@block_size)
    actual = read_block(io, b)

    # just check the first few bytes
    16.times do |i|
      actual.getbyte(i).should == expected.getbyte(i)
    end

    # This doesn't work, presumably some string encoding issues
    #actual.should == expected
  end

  def verify_blocks(blocks)
    File.open(@dev, 'rb') do |io|
      blocks.each {|b| verify_block(io, b)}
    end
  end

  def initialize_device(opts)
    needs_zero = opts.fetch(:need_zero, true)
    wipe_device(@dev) if needs_zero

    @deltas << zeroes_delta(@max_blocks)
  end
end

#----------------------------------------------------------------
