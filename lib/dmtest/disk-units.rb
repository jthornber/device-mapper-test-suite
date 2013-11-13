#----------------------------------------------------------------

module DiskUnits
  def sectors(n)
    n
  end

  def k(n)
    n * 2
  end

  def meg(n)
    n * sectors(2048)
  end

  def gig(n)
    meg(n) * 1024
  end

  def tera(n)
    gig(n) * 1024
  end
end

#----------------------------------------------------------------

