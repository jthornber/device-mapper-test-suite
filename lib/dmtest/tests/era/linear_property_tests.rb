require 'dmtest/pattern_stomper'
require 'dmtest/test-utils'
require 'dmtest/era_stack'
require 'dmtest/era_utils'
require 'dmtest/thinp-test'
require 'dmtest/utils'

require 'rspec/expectations'

#----------------------------------------------------------------

class LinearPropertyTests < ThinpTestCase
  include EraUtils
  include Utils
  include DiskUnits
  extend TestUtils

  def setup
    super
  end

  def make_stack(opts = Hash.new)
    EraStack.new(@dm, @metadata_dev, @data_dev, opts)
  end

  #--------------------------------

  define_test :prepare_on_origin_then_check_era do
    s = make_stack(:format => true)
    s.activate_support_devs do
      ps = PatternStomper.new(s.origin.path, k(32), :need_zero => true)
      ps.stamp(20)
      ps.verify(0, 1)

      s.activate_top_level do
        ps2 = ps.fork(s.era.path)
        ps2.verify(0, 1)
      end

      ps.verify(0, 1)
    end
  end

  define_test :prepare_on_era_then_check_origin do
    s = make_stack(:format => true)
    s.activate_support_devs do
      ps2 = nil

      s.activate_top_level do
        ps = PatternStomper.new(s.era.path, k(32), :need_zero => true)
        ps.stamp(20)
        ps.verify(0, 1)

        ps2 = ps.fork(s.origin.path)
      end

      ps2.verify(0, 1)
    end
  end

  define_test :prepare_era_then_check_after_reload do
    ps = nil

    s = make_stack(:format => true)
    s.activate do
      ps = PatternStomper.new(s.era.path, k(32), :need_zero => true)
      ps.stamp(20)
    end

    s.activate do
      ps2 = ps.fork(s.era.path)
      ps2.verify(0, 1)
    end
  end

  define_test :dt_a_new_era_device do
    s = EraStack.new(@dm, @metadata_dev, @data_dev, :format => true)
    s.activate do
      dt_device(s.era)
    end
  end
end

#----------------------------------------------------------------
