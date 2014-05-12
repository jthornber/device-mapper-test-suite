class WriteboostStatus
  PATTERN ='\d+\s+\d+\s+writeboost\s+(.*)'
  def self.from_raw_status(raw_output)
    m = raw_output.match(PATTERN)
    raise "Couldn't parse writeboost status" if m.nil?
    WriteboostStatus.new m[1]
  end

  TUNABLES = ["barrier_deadline_ms",
              "allow_migrate",
              "enable_migration_modulator",
              "migrate_threshold",
              "nr_max_batched_migration",
              "update_record_interval",
              "sync_interval"]

  STAT_WRITE = 3
  STAT_HIT = 2
  STAT_ON_BUFFER = 1
  STAT_FULLSIZE = 0

  def initialize(output)
    @tbl = {}
    parse(output)
  end

  def [](key)
    @tbl[key]
  end

  def stat(write, hit, on_buffer, fullsize)
    mask = (write     << STAT_WRITE)     + 
           (hit       << STAT_HIT)       +
           (on_buffer << STAT_ON_BUFFER) +
           (fullsize  << STAT_FULLSIZE)
    @tbl["stat"][mask]
  end

  # Format stat as readable table
  def format_stat_table
    def stat_bool(i, shift)
      (i & (1 << shift)) == 0 ? 0 : 1
    end

    arr = ["write? hit? on_buffer? fullsize? count"]
    16.times do |i|
      count = @tbl["stat"][i]
      a, b, c, d = [STAT_WRITE, STAT_HIT, STAT_ON_BUFFER, STAT_FULLSIZE]
                   .map { |shift| stat_bool(i, shift) }
      arr += [[a, b, c, d, count].join(" ")] 
    end
    arr.join("\n")
  end

  private
  def parse(output)
    arr = output.split.reverse
    before_stat = ["cursor_pos", "nr_cache_blocks", "nr_segments", "current_id", "last_flushed_id", "last_migrated_id", "nr_dirty_cache_blocks"]

    before_stat.size.times do |i|
      v = arr.pop(1).first.to_i
      k = before_stat[i] 
      @tbl[k] = v
    end

    @tbl["stat"] = []
    16.times do |i|
      v = arr.pop(1).first.to_i
      @tbl["stat"][i] = v
    end

    v = arr.pop(1).first.to_i
    @tbl["nr_partial_flushed"] = v

    nr_tunables = arr.pop(1).first.to_i # nr tunables
    raise "Incorrect nr_tunables(#{nr_tunables})" unless nr_tunables == TUNABLES.size * 2

    TUNABLES.size.times do
      _v, k = arr.pop(2)
      v = _v.to_i
      @tbl[k] = v
    end
    # p @tbl
  end
end

if __FILE__ == $0
  x = (1..24).to_a
  names = ["barrier_deadline_ms",
           "allow_migrate",
           "enable_migration_modulator",
           "migrate_threshold",
           "nr_max_batched_migration",
           "update_record_interval",
           "sync_interval"]
  y = (25..31).to_a
  _output = x + [14] + names.zip(y).flatten
  output = _output.join(" ")
  # p output

  st = WriteboostStatus.new(output)

  p st["nr_segments"]
  p st.stat(1, 0, 1, 0)
  puts st.format_stat_table

  p WriteboostStatus.from_raw_status("11 12 writeboost " + output)
end
