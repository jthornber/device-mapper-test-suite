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
    if complete
      /C ([DRW]) (\d+) (\d+)/
    else
      /Q ([DRW]) (\d+) (\d+)/
    end
  end

  def blkparse(dev, complete)
    # we need to work out what blktrace called this dev
    path = File.basename(follow_link(dev.to_s))

    events = Array.new
    pattern = parse_pattern(complete)

    `blkparse -f \"%a %d %S %N\n\" #{path}`.lines.each do |l|
      m = pattern.match(l)
      events.push(Event.new(to_event_type(m[1]), m[2].to_i, m[3].to_i / 512)) if m
    end

    events
  end

  def blktrace_(devs, complete, &block)
    path = 'trace'

    consumer = LogConsumer.new

    flags = ''
    devs.each_index {|i| flags += "-d #{devs[i]} "}
    child = ProcessControl::Child.new(consumer, "blktrace #{flags}")
    begin
      sleep 0.1                     # FIXME: how can we avoid this race?
      r = block.call
    ensure
      child.interrupt
    end

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
end
