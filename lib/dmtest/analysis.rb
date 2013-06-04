require 'dmtest/xml_format'

require 'pp'

#----------------------------------------------------------------

# In sectors, not blocks as in the mapping structs
LogicalSegment = Struct.new(:length, :physical_segments)
PhysicalSegment = Struct.new(:origin_begin, :data_begin, :length)

class MetadataAnalysis
  include XMLFormat

  def initialize(md)
    @md = md
  end

  def block_length_histograms
    @md.devices.each do |dev|
      puts "device #{dev.dev_id}"
      block_length_histogram(dev)
      puts ""
    end
  end

  def fragmentations
    @md.devices.each do |dev|
      puts "device #{dev.dev_id}"
      printf("  %10s %10s %10s\n",
             'io size', 'seeks/io', 'distance/seek')
      puts "  --------------------------------------"

      power = 0
      loop do
        io_size = 8 * 4 ** power

        r = fragmentation(dev, @md.superblock.data_block_size, io_size)
        break if r.nil?
        seeks, dist = r

        printf("  %10s\t%.3f\t%s\n",
               segments_to_human(io_size),
               seeks, segments_to_human(dist.to_i))

        power += 1
      end
    end
  end

  private

  GRANULARITY = 2 * 4
  Unit = Struct.new(:factor, :abbrev)

  def segments_to_human(size)
    units = [Unit.new(2048 * 1024, 'g'),
             Unit.new(2048, 'm'),
             Unit.new(2, 'k')]

    units.each do |u|
      if size >= u.factor
        return "#{size / u.factor}#{u.abbrev}"
      end
    end

    "#{size * 512}b"
  end

  def round_down(n, d)
    (n / d) * d
  end

  def rand_io(max, io_size)
    round_down(rand(max - io_size), 8)
  end

  def mappings_to_phys_segments(mappings, block_size)
    mappings.map do |m|
      PhysicalSegment.new(m.origin_begin * block_size,
                          m.data_begin * block_size,
                          m.length * block_size)
    end
  end

  # FIXME: test this
  def to_logical_segments(p_segs)
    l_segs = Array.new

    if p_segs.empty?
      return l_segs
    end

    while !p_segs.empty?
      a = Array.new

      p = p_segs.shift
      a << p

      while !p_segs.empty? && (p_segs[0].origin_begin == p.origin_begin + p.length)
        p = p_segs.shift
        a << p
      end

      l_segs << LogicalSegment.new(a.inject(0) {|tot, ps| tot + ps.length}, a)
    end

    l_segs
  end

  def unique_ios_per_lseg(lseg, io_size, granularity)
    (lseg.length < io_size) ? 0 : ((lseg.length - io_size) / granularity) + 1
  end

  # |pre| and |post| are the length in the lseg before and after the junction
  # FIXME: check this
  def ios_that_overlap_junction(pre, post, io_size, granularity)
    pre /= granularity
    post /= granularity
    io_size /= granularity

    intersections = io_size - 1
    r = intersections

    if pre < io_size
      r -= intersections - pre
    end

    if post < io_size
      r -= intersections - post
    end

    r
  end

  #--------------------------------------------------------------
  # Fragmentation is dependent on the IO pattern; if you're doing
  # random IO of 4k blocks then your device is never fragmented.
  #
  # For a random IO, to a mapped region, of size X what is the
  # expected nr and distance of seeks experienced? (not including the
  # initial seek to the start of the data)
  #
  # We only generate IOs to mapped areas.
  #--------------------------------------------------------------
  def fragmentation(dev, block_size, io_size)
    # Break the mappings up into logical segments.  Each segment will
    # have one or more physical segments.
    logical_segments = to_logical_segments(mappings_to_phys_segments(dev.mappings, block_size))

    total_ios = 0.0
    total_seeks = 0.0
    total_seek_distance = 0.0

    logical_segments.each do |lseg|
      # calculate the nr of different ios of |io_size| can fit into
      nr_ios = unique_ios_per_lseg(lseg, io_size, GRANULARITY)
      next if nr_ios == 0
      
      total_ios += nr_ios

      # now we look at the junctions between physical segments
      pre = 0
      post = lseg.length
      psegs = lseg.physical_segments
      if psegs.length > 1
        0.upto(psegs.length - 2) do |i|
          l = psegs[i].length
          pre += l
          post -= l
          nr_seeks = ios_that_overlap_junction(pre, post, io_size, GRANULARITY)

          total_seeks += nr_seeks

          # FIXME: check we can handle these large numbers
          total_seek_distance += nr_seeks * ((psegs[i].data_begin + psegs[i].length) - psegs[i + 1].data_begin).abs
        end
      end
    end

    (total_ios == 0) ? nil :
      [total_seeks / total_ios, total_seeks > 0 ? total_seek_distance / total_seeks : 0]
  end

  # assumes the pairs are sorted
  def format_histogram(pairs)
    width = 80

    m = pairs.inject(0) {|m, p| m = [m, p[1]].max}

    pairs.each do |bin, count|
      printf("%-8d: %s\n", 2 ** bin, '*' * (width * count / m))
    end
  end

  def block_length_histogram(dev)
    histogram = Hash.new {|hash, key| hash[key] = 0}

    dev.mappings.each do |m|
      histogram[nearest_power(m.length)] += m.length
    end

    format_histogram(histogram.sort)
  end

  def nearest_power(n)
    1.upto(32) do |p|
      if 2 ** p > n
        return p - 1
      end
    end
  end
end

#----------------------------------------------------------------
