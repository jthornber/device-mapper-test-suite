require 'dmtest/log'
require 'dmtest/process'

module BlkTrace
  include ProcessControl

  Event = Struct.new(:code, :start_sector, :len_sector)

  def follow_link(path)
    File.symlink?(path) ? File.readlink(path) : path
  end

  def to_event_type(cs)
    r = Array.new

    cs.each_char do |c|
      case c
      when 'D'
        r << :discard

      when 'R'
        r << :read

      when 'W'
        r << :write

      when 'S'
        r << :sync

      else
        raise "Unknown blktrace event type: '#{c}'"
      end
    end

    r
  end

  def filter_events(event_type, events)
    # FIXME: support multiple event_types?
    r = Array.new
    events.each_index do |i|
      r.push(events[i]) if events[i].code.member?(event_type)
    end
    r
  end

  def assert_discard(traces, start_sector, length)
    assert(traces[0].member?(Event.new([:discard], start_sector, length)))
  end

  def assert_discards(traces, start_sector, length)
    events = filter_events(:discard, traces)
    assert(!events.empty?)


    start = events[0].start_sector
    len = events[0].len_sector

# FIXME: I can see what this is trying to do, but it's not checking
# the space is contiguous, or duplicate.
#    events.each do |event|
#      start = event.start_sector if event.start_sector < start
#      len += event.len_sector
#    end

    assert_equal(start_sector, start)
    assert_equal(length, len)
  end

  def parse_pattern(complete)
    # The S (sleep requested) action can be present in addition to the ones we're interested in
    if complete
      /C ([DRW])S? (\d+) (\d+)/
    else
      /Q ([DRW])S? (\d+) (\d+)/
    end
  end

  def blkparse_(dev, complete)
    # we need to work out what blktrace called this dev
    path = File.basename(follow_link(dev.to_s))

    pattern = parse_pattern(complete)

    IO.popen("blkparse -f \"%a %d %S %N\n\" #{path}") do |f|
      f.each_line do |l|
        m = pattern.match(l)
        yield Event.new(to_event_type(m[1]), m[2].to_i, m[3].to_i / 512) if m
      end
    end
  end

  def blkparse(dev, complete)
    events = Array.new

    blkparse_(dev, complete) { |e| events << e }

    events
  end

  def run_blktrace(devs, complete, &block)
    path = 'trace'

    consumer = LogConsumer.new

    flags = '-b 8192 '
    devs.each_index {|i| flags += "-d #{devs[i]} "}
    flags += complete ? "-a complete " : "-a queue "
    child = ProcessControl::Child.new(consumer, "blktrace #{flags}")
    begin
      sleep 0.1                     # FIXME: how can we avoid this race?
      r = block.call
    ensure
      child.interrupt
    end

    r
  end

  def blktrace_(devs, complete, &block)
    r = run_blktrace(devs, complete, &block)

    # results is an Array of Event arrays (one per device)
    results = devs.map {|d| blkparse(d, complete)}
    [results, r]
  end

  def blktrace(*devs, &block)
    blktrace_(devs, false, &block)
  end

  def blktrace_complete(*devs, &block)
    blktrace_(devs, true, &block)
  end

  #--------------------------------

  class IOHistogram
    def initialize(name, dev_size, nr_bins)
      @name = name
      @divisor = dev_size / nr_bins
      @bins = Array.new(nr_bins) {0}
    end

    def record_io(start_sector, len)
      return if len == 0

      start_bin = to_bin(start_sector)
      end_bin = to_bin(start_sector + len - 1)
      for b in start_bin..end_bin
        @bins[b] = @bins[b] + 1
      end
    end

    def show_histogram
      STDERR.puts "#{@name}: #{@bins.join(", ")}"
    end

    private
    def to_bin(sector)
      sector / @divisor
    end
  end

  def blktrace_histogram(dev, &block)
    run_blktrace([dev], false, &block)

    read_histogram = IOHistogram.new("read", dev_size(dev), 128)
    write_histogram = IOHistogram.new("write", dev_size(dev), 128)

    blkparse_(dev, false) do |e|
      if e.code.member?(:write)
        write_histogram.record_io(e.start_sector, e.len_sector)
      elsif e.code.member?(:read)
        read_histogram.record_io(e.start_sector, e.len_sector)
      end
    end

    read_histogram.show_histogram
    write_histogram.show_histogram
  end
end
