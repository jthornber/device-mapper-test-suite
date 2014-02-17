#----------------------------------------------------------------

module EraUtils
  include DiskUnits

  def dump_metadata(dev, opts = {})
    logical_flag = opts.fetch(:logical, false) ? "--logical" : ""
    STDERR.puts "logical flag = '#{logical_flag}'"
    output = ProcessControl.run("era_dump #{logical_flag} #{dev}")
    # FIXME: finish
  end

  def blocks_changed_since(dev, era)
    output = ProcessControl.run("era_invalidate --written-since #{era} #{dev}")
  end
end

#----------------------------------------------------------------
