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
end

#----------------------------------------------------------------
