require 'dmtest/log'

#----------------------------------------------------------------

class EraStatus
  attr_accessor :md_block_size, :md_used, :md_total, :current_era, :metadata_snap

  PATTERN ='\d+\s+\d+\s+era\s+(.*)'

  def initialize(dev)
    m = dev.status.match(PATTERN)
    raise "couldn't parse era status" if m.nil?

    @a = m[1].split

    shift_int :md_block_size
    shift_ratio :md_used, :md_total
    shift_int :current_era
    shift_maybe_int :metadata_snap
  end

  private
  def check_args(symbol)
    raise "Insufficient status fields, while trying to read #{symbol}" if @a.size == 0
  end

  def shift_(symbol)
    check_args(symbol)
    @a.shift
  end

  def shift(symbol)
    check_args(symbol)
    set_val(symbol, @a.shift)
  end

  def shift_int_(symbol)
    check_args(symbol)
    Integer(@a.shift)
  end

  def shift_int(symbol)
    check_args(symbol)
    set_val(symbol, Integer(@a.shift))
  end

  def shift_ratio(sym1, sym2)
    str = shift_(sym1)
    a, b = str.split('/')
    set_val(sym1, a.to_i)
    set_val(sym2, b.to_i)
  end

  def shift_maybe_int(symbol)
    check_args(symbol)
    v = @a.shift
    if v == '-'
      set_val(symbol, nil)
    else
      set_val(symbol, Integer(v))
    end
  end

  def set_val(symbol, v)
    self.send("#{symbol}=".intern, v)
  end
end

#----------------------------------------------------------------
