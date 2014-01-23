#----------------------------------------------------------------

module EraUtils
  include DiskUnits

  def dump_metadata(dev)
    output = ProcessControl.run("era_dump #{dev}")
    # FIXME: finish
  end
end

#----------------------------------------------------------------
