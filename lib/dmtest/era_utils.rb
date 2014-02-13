#----------------------------------------------------------------

module EraUtils
  include DiskUnits

  def dump_metadata(dev)
    output = ProcessControl.run("era_dump #{dev}")
    # FIXME: finish
  end

  def blocks_changed_since(dev, era)
    output = ProcessControl.run("era_invalidate --written-since #{era} #{dev}")
  end
end

#----------------------------------------------------------------
