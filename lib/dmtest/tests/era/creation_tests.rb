require 'dmtest/tests/era/era_stack'
require 'dmtest/thinp-test'
require 'dmtest/test-utils'
require 'dmtest/utils'

require 'rspec/expectations'

#----------------------------------------------------------------

class CreationTests < ThinpTestCase
  include Utils
  include DiskUnits
  extend TestUtils

  def setup
    super
  end

  def test_bring_up_an_era_target
    s = EraStack.new(@dm, @metadata_dev, @data_dev, :format => true)
    s.activate do
    end
  end
end

#----------------------------------------------------------------
