require 'config'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/blktrace'
require 'pp'

#----------------------------------------------------------------

class FakeDiscardTests < ThinpTestCase
  include Tags
  include Utils
  include BlkTrace

  def setup
    super
    @data_block_size = 256 # granularity defaults to @data_block_size
  end

  def assert_not_supported(opts)
    with_fake_discard(opts) do |dev|
      assert_raise(Errno::EOPNOTSUPP) do
        dev.discard(0, @data_block_size)
      end
    end
  end

  def test_disable_discard
    assert_not_supported(:discard_support => false)
  end

  def test_enable_discard
    with_fake_discard do |dev|
      traces, _ = blktrace(dev) do
        dev.discard(0, @data_block_size)
      end

      assert_discard(traces, 0, @data_block_size)
    end
  end

  def verify_discard(dev, start, len)
        traces, _ = blktrace(dev) do
          dev.discard(start, len)
        end
        assert_discards(traces[0], start, len)
  end

  def test_granularity
    [64, 128, 1024].each do |gran|
      with_fake_discard(:granularity => gran, :max_discard_sectors => 128 * gran) do |dev|
        verify_discard(dev, 0, gran * 3)
        verify_discard(dev, gran - 1, gran * 3)
      end
    end
  end

  def test_granularity_equals_max_discard
    [64, 128, 1024].each do |gran|
      with_fake_discard(:granularity => gran, :max_discard_sectors => gran) do |dev|
        verify_discard(dev, 0, gran * 3)
        verify_discard(dev, gran - 1, gran * 3)
      end
    end
  end

end
