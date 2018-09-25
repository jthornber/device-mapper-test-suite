#----------------------------------------------------------------

module MathUtils
  def round_up(n, d)
    n += d - 1
    n -= n % d
    n
  end

  def div_up(n, d)
    (n + (d - 1)) / d
  end

  def round_down(n, d)
    (n / d) * d
  end

  def is_power_of_2?(n)
    (n != 0 && ((n & (n - 1)) == 0))
  end
end

#----------------------------------------------------------------
