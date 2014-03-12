require 'dmtest/era_stack'
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
    s.activate {}
  end

  # This fails because we don't have enough metadata space
  def _test_largest_valid_origin
    biggest = 137438953408      # 2^31 - 1 * 32k blocks

    table = Table.new(ErrorTarget.new(biggest))
    with_dev(table) do |fake_data|
      s = EraStack.new(@dm, @data_dev, fake_data,
                       :origin_size => biggest,
                       :block_size => 64,
                       :format => true)

      s.activate {}
    end
  end

  def test_smallest_invalid_origin
    too_big = 137438953472      # 2^31 * 32k blocks

    table = Table.new(ErrorTarget.new(too_big))
    with_dev(table) do |fake_data|
      s = EraStack.new(@dm, @metadata_dev, fake_data,
                       :origin_size => too_big,
                       :block_size => 64,
                       :format => true)

      failed = false
      begin
        s.activate {}
      rescue
        failed = true
      end

      failed.should be_true
    end
  end
end

#----------------------------------------------------------------
