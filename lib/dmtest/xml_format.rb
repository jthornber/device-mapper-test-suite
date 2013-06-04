# The thin_dump and thin_restore use an xml based external
# representation of the metadata.  This module gives the test suite
# access to this xml data.

#----------------------------------------------------------------

require 'rexml/document'
require 'rexml/streamlistener'

module XMLFormat
  include REXML

  SUPERBLOCK_FIELDS = [[:uuid, :string],
                       [:time, :int],
                       [:transaction, :int],
                       [:data_block_size, :int],
                       [:nr_data_blocks, :int]]

  MAPPING_FIELDS = [[:origin_begin, :int],
                    [:data_begin, :int],
                    [:length, :int],
                    [:time, :int]]

  DEVICE_FIELDS = [[:dev_id, :int],
                   [:mapped_blocks, :int],
                   [:transaction, :int],
                   [:creation_time, :int],
                   [:snap_time, :int],
                   [:mappings, :object]]

  def self.field_names(flds)
    flds.map {|p| p[0]}
  end

  Superblock = Struct.new(*field_names(SUPERBLOCK_FIELDS))
  Mapping = Struct.new(*field_names(MAPPING_FIELDS))
  Device = Struct.new(*field_names(DEVICE_FIELDS))
  Metadata = Struct.new(:superblock, :devices)

  class Listener
    include REXML::StreamListener

    attr_reader :metadata

    def initialize
      @metadata = Metadata.new(nil, Array.new)
    end

    def to_hash(pairs)
      r = Hash.new
      pairs.each do |p|
        r[p[0].intern] = p[1]
      end
      r
    end

    def get_fields(attr, flds)
      flds.map do |n,t|
        case t
        when :int
          attr[n].to_i

        when :string
          attr[n]

        when :object
          attr[n]

        else
          raise "unknown field type"
        end
      end
    end

    def tag_start(tag, args)
      attr = to_hash(args)

      case tag
      when 'superblock'
        @metadata.superblock = Superblock.new(*get_fields(attr, SUPERBLOCK_FIELDS))

      when 'device'
        attr[:mappings] = Array.new
        @current_device = Device.new(*get_fields(attr, DEVICE_FIELDS))
        @metadata.devices << @current_device

      when 'single_mapping'
        @current_device.mappings << Mapping.new(attr[:origin_block].to_i, attr[:data_block].to_i, 1, attr[:time])

      when 'range_mapping'
        @current_device.mappings << Mapping.new(*get_fields(attr, MAPPING_FIELDS))

      else
        puts "unhandled tag '#{tag} #{attr.map {|x| x.inspect}.join(', ')}'"
      end
    end

    def tag_end(tag)
    end

    def text(data)
      return if data =~ /^\w*$/ # ignore whitespace
      abbrev = data[0..40] + (data.length > 40 ? "..." : "")
      puts "  text    :    #{abbrev.inspect}"
    end
  end

  def read_xml(io)
    l = Listener.new
    Document.parse_stream(io, l)
    l.metadata
  end

  class Emitter
    def initialize(out)
      @out = out
      @indent = 0
    end

    def emit_tag(obj, tag, *fields, &block)
      expanded = fields.map {|fld| "#{fld}=\"#{obj.send(fld)}\""}
      if block.nil?
        emit_line "<#{tag} #{expanded.join(' ')}/>"
      else
        emit_line "<#{tag} #{expanded.join(' ')}>"
        push
        yield unless block.nil?
        pop
        emit_line "</#{tag}>"
      end
    end

    def emit_line(str)
      @out.puts((' ' * @indent) + str)
    end

    def push
      @indent += 2
    end

    def pop
      @indent -= 2
    end
  end

  def emit_superblock(e, sb, &block)
    e.emit_tag(sb, 'superblock', :uuid, :time, :transaction, :data_block_size, :nr_data_blocks, &block)
  end

  def emit_device(e, dev, &block)
    e.emit_tag(dev, 'device', :dev_id, :mapped_blocks, :transaction, :creation_time, :snap_time, &block)
  end

  def emit_mapping(e, m)
    if m.length == 1
      e.emit_line("<single_mapping origin_block=\"#{m.origin_begin}\" data_block=\"#{m.data_begin}\" time=\"#{m.time}\"/>")
    else
      e.emit_tag(m, 'range_mapping', :origin_begin, :data_begin, :length, :time)
    end
  end

  def write_xml(metadata, io)
    e = Emitter.new(io)

    emit_superblock(e, metadata.superblock) do
      metadata.devices.each do |dev|
        emit_device(e, dev) do
          dev.mappings.each do |m|
            emit_mapping(e, m)
          end
        end
      end
    end
  end

  #--------------------------------------------------------------

  def get_device(md, dev_id)
    md.devices.each do |dev|
      if dev.dev_id == dev_id
        return dev
      end
    end
  end

  # Turns 2 lists of mappings, into a list of pairs of mappings.
  # These pairs cover identical regions.  nil is used for the
  # data_begin if that region isn't mapped.
  def expand_mappings(left, right)
    pairs = Array.new
    i1 = 0
    i2 = 0

    m1 = left[i1]
    m2 = right[i2]

    # look away now ...
    loop do
      if !m1 && !m2
        return pairs
      elsif !m1
        pairs << [Mapping.new(m2.origin_begin, nil, m2.length, m2.time),
                  m2]
        m2 = nil
      elsif !m2
        pairs << [m1,
                  Mapping.new(m1.origin_begin, nil, m1.length, m1.time)]
        m1 = nil
      elsif m1.origin_begin < m2.origin_begin
        if m1.origin_begin + m1.length <= m2.origin_begin
          pairs << [Mapping.new(m1.origin_begin, m1.data_begin, m1.length, m1.time),
                    Mapping.new(m1.origin_begin, nil, m1.length, m1.time)]
          i1 += 1
          m1 = left[i1]
        else
          len = m2.origin_begin - m1.origin_begin
          pairs << [Mapping.new(m1.origin_begin, m1.data_begin, len, m1.time),
                    Mapping.new(m1.origin_begin, nil, len, m1.time)]
          m1 = Mapping.new(m1.origin_begin + len, m1.data_begin + len, m1.length - len, m1.time)
        end
      elsif m2.origin_begin < m1.origin_begin
        if m2.origin_begin + m2.length <= m1.origin_begin
          pairs << [Mapping.new(m2.origin_begin, nil, m2.length, m2.time),
                    Mapping.new(m2.origin_begin, m2.data_begin, m2.length, m2.time)]
          i2 += 1
          m2 = right[i2]
        else
          len = m1.origin_begin - m2.origin_begin
          pairs << [Mapping.new(m2.origin_begin, nil, len, m2.time),
                    Mapping.new(m2.origin_begin, m2.data_begin, len, m2.time)]
          m2 = Mapping.new(m2.origin_begin + len, m2.data_begin + len, m2.length - len, m2.time)
        end
      else
        len = [m1.length, m2.length].min
        pairs << [Mapping.new(m1.origin_begin, m1.data_begin, len, m1.time),
                  Mapping.new(m1.origin_begin, m2.data_begin, len, m2.time)]
        if m1.length < m2.length
          i1 += 1
          m1 = left[i1]
          m2 = Mapping.new(m2.origin_begin + len, m2.data_begin + len, m2.length - len, m2.time)
        elsif m2.length < m1.length
          i2 += 1
          m1 = Mapping.new(m1.origin_begin + len, m1.data_begin + len, m1.length - len, m1.time)
          m2 = right[i2]
        else
          i1 += 1
          i2 += 1
          m1 = left[i1]
          m2 = right[i2]
        end
      end
    end
  end

  # returns 3 arrays of mappings: unique to first arg, common, unique
  # to second arg
  def compare_devs(md_dev1, md_dev2)
    m1 = md_dev1.mappings
    m2 = md_dev2.mappings

    left = Array.new
    center = Array.new
    right = Array.new

    expand_mappings(m1, m2).each do |pair|
      if pair[0].data_begin == pair[1].data_begin &&
          pair[0].time == pair[1].time
        # mappings are the same
        center << pair[0]
      else
        left << pair[0]
        right << pair[1]
      end
    end

    [left, center, right].each {|a| a.reject {|e| e.data_begin == nil}}
    [left, center, right]
  end

  def compare_thins(md1, md2, dev_id)
    compare_devs(get_device(md1, dev_id),
                 get_device(md2, dev_id))
  end
end

#----------------------------------------------------------------
