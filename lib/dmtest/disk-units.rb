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
    n * meg(1) * 1024
  end
end

#----------------------------------------------------------------

