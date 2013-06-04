require 'dmtest/device-mapper/instr'
require 'dmtest/tiny_volume_manager/metadata'
require 'test/unit'
require 'pp'
require 'set'

#----------------------------------------------------------------

class MetadataRender
  include Metadata

  def initialize(out_stream)
    @out = out_stream
    @indent = 0
  end

  def display_metadata
    Volume.find(:all).each do |v|
      emit v
      indent {display_segments(v.segments)}
      emit ''
    end

    display_free_space
  end

  def display_segments(ss)
    ss.each do |s|
      emit s
      emit s.target unless s.target.nil?
      indent {display_segments(s.children)} if s.children
    end
  end

  def display_free_space
    emit "free space:"
    indent do
      Segment.find(:all, :conditions => "parent_id IS NULL and target_id IS NULL").each do |s|
        emit s
      end
    end
  end

  private
  INDENT = 4

  def indent
    @indent += INDENT
    yield
    @indent -= INDENT
  end

  def emit(str)
    @out.puts "#{' ' * @indent}#{str}"
  end
end

module VolumeActivation
  include DM::LowLevel
  include DM::MediumLevel

  class ActivationAccumulator
    def initialize
      @seen = Set.new
      @order = Array.new
    end

    def push(volume)
      unless @seen.member?(volume.id)
        @seen.add(volume.id)
        @order << volume
        return true
      end

      return false
    end

    def results
      @order.reverse
    end
  end

  # FIXME: move to HIR
  class ReversableOp
    attr_accessor :forwards, :backwards

    def initialize(forwards_mir, backwards_mir)
      @forwards = forwards_mir
      @backwards = backwards_mir
    end

    def compile
      [@forwards, @backwards]
    end
  end

  class SequenceReversableOp
    def initialize(*steps)
      @steps = steps
    end

    def compile
      @steps.reverse.inject do |acc, instr|
        compile2(instr, acc)
      end
    end

    private
    def compile2(first, second)
      f1, b1 = first.compile
      f2, b2 = second.compile

      [Sequence.new(f1, f2, OnFail.new(b1)),
       Sequence.new(b2, b1)]
    end
  end

  def activate(volume)
    volumes = walk_dependencies(volume).reject(&:is_pv?)

    instrs = volumes.map do |v|
      segs = v.segments.find_all {|s| !s.target.nil?}
      table = DM::Table.new(*segs.map {|s| s.target.to_dm_target})

      ReversableOp.new(BasicBlock.new([create(v.name),
                                       load(v.name, table)]),
                       BasicBlock.new([remove(v.name)]))
    end

    prog = SequenceReversableOp.new(instrs)
    compile(prog.compile[0]).pp
  end

  private
  def walk_dependencies(volume, acc = ActivationAccumulator.new)
    return unless acc.push(volume)

    volume.segments.each do |s|
      if s.target
        s.target.deps.each {|dep| walk_dependencies(dep, acc)}
      end

      s.children.each do |c|
        walk_dependencies(c.volume, acc)
      end
    end

    acc.results
  end
end

module VolumeCreation
  include Metadata

  def add_pv(name, uuid, length)
    pv = Volume.create(:name => name, :uuid => uuid)

    # This segment represents free space because it has no parent
    # segment or associated target.
    pv.segments.create(:offset => 0, :length => length)
    pv
  end

  def create_pool(name, metadata_dev, data_dev)
    lv = Volume.create(:name => name, :uuid => generate_uuid)

    seg = Segment.new(:offset => 0, :length => data_dev.length)
    seg.target = PoolTarget.new(:metadata_id => metadata_dev.id,
                                :data_id => data_dev.id,
                                :block_size => 128,
                                :low_water_mark => 0,
                                :block_zeroing => true,
                                :discard => true,
                                :discard_passdown => true)
    lv.segments << seg
    lv
  end

  def create_thin(name, pool, dev_id, length)
    lv = Volume.create(:name => name, :uuid => generate_uuid)

    seg = Segment.new(:offset => 0, :length => length)
    seg.target = ThinTarget.new(:pool_id => pool.id,
                                :dev_id => dev_id)
    lv.segments << seg
    lv
  end

  private
  def generate_uuid
    "blah-blah-blah"
  end
end

class VolumeGroup
  include Metadata
  include VolumeActivation
  include VolumeCreation
end

#----------------------------------------------------------------

class TVMMetadataTests < Test::Unit::TestCase
  include Metadata

  DB_FILE = './metadata.db'
  CONNECTION_PARAMS = {
    :adapter => 'sqlite3',
    :database => DB_FILE
  }

  def setup
    File.delete(DB_FILE)
    open_metadata
    super
  end

  def teardown
    close_metadata
  end

  def close_metadata
    @metadata.close
  end

  def open_metadata
    @metadata = MetadataStore.new(CONNECTION_PARAMS)
  end

  def reopen_metadata
    close_metadata
    open_metadata
  end

  def display_metadata
    r = MetadataRender.new(STDOUT)
    r.display_metadata
  end

  def test_create_store
    extent_size = 8196

    vg = VolumeGroup.new
    pv0 = vg.add_pv('/dev/vdc', 'KBMvbK-ZKHF-giLJ-MEqp-dgb7-j0r7-Q8iC0U', 93458 * extent_size)
    pv1 = vg.add_pv('/dev/vdd', 'KeR3R0-dQd8-CCnb-1iS7-ndev-1sLW-tT9fTF', 476931 * extent_size)
    pv2 = vg.add_pv('/dev/vde', 'goKzR9-znn6-v0d6-cOfj-8fe7-Lflf-7f0Rwt', 28618 * extent_size)

    # Logical volumes
    pool = vg.create_pool('pool0', pv0, pv1)
    thin0 = vg.create_thin('vm1', pool, 101, 12345)
    thin1 = vg.create_thin('vm2', pool, 1000, 898723)

    vg.activate(thin0)

    # ubuntu_root = Volume.create(:name => 'ubuntu_root',
    #                             :uuid => 'NWavSx-2cPb-vk8n-387g-OWsZ-884y-tw0Lwy')

    # # This is a logical segment
    # stripe = StripedTarget.new(:nr_stripes => 1)
    # lv_seg = Segment.create(:offset => 0,
    #                         :length => 9536 * extent_size)
    # lv_seg.target = stripe
    # ubuntu_root.segments << lv_seg

    # # Underneath the logical segment are some physical segments
    # pv_seg = lv_seg.children.create(:offset => 0,
    #                                 :length => 9536 * extent_size)
    # pv2.segments << pv_seg

    #display_metadata
  end
end

#----------------------------------------------------------------
