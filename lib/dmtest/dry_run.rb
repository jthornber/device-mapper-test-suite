require 'dmtest/log'

#----------------------------------------------------------------

module DryRun
  def DryRun.run(default)
    if ENV['THIN_TESTS'] == 'EXECUTE'
      yield
    else
      default
    end
  end
end

#----------------------------------------------------------------
