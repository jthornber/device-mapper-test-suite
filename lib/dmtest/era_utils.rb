#----------------------------------------------------------------

module EraUtils
  include DiskUnits

  def blocks_changed_since(dev, era)
    output = ProcessControl.run("era_invalidate --written-since #{era} #{dev}")
  end
end

#----------------------------------------------------------------
