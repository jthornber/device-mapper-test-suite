require 'dmtest/pattern_stomper'
require 'dmtest/test-utils'
require 'dmtest/tests/era/era_stack'
require 'dmtest/tests/era/era_utils'
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

  def test_prepare_on_origin_then_check_era
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

  def test_prepare_on_era_then_check_origin
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

  def test_prepare_era_then_check_after_reload
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

  # FIXME: move to a different test class
  def test_wiped_blocks_have_increasing_eras
    s = make_stack(:format => true)
    s.activate_support_devs do
       s.activate_top_level do

        block_size = k(64) * 1024
        nr_blocks = dev_size(s.era) / block_size

        0.upto(nr_blocks - 1) do |block|
          STDERR.puts "wiping block #{block}"
          ProcessControl.run("dd if=/dev/zero of=#{s.era.path} oflag=direct bs=#{block_size * 512} seek=#{block} count=1")
          s.era.message(0, "checkpoint")
        end
      end

      STDERR.puts
      STDERR.puts dump_metadata(s.md)
    end
  end

  def test_dt_a_new_era_device
    s = EraStack.new(@dm, @metadata_dev, @data_dev, :format => true)
    s.activate do
      dt_device(s.era)
    end
  end
end

#----------------------------------------------------------------
