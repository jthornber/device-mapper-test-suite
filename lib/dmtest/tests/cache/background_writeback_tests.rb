require 'dmtest/blktrace'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/tests/cache/cache_stack'
require 'dmtest/tests/cache/policy'
require 'dmtest/tests/cache/cache_utils'

require 'thinp_xml/cache_xml'

#----------------------------------------------------------------

class BackgroundWritebackTests < ThinpTestCase
  include GitExtract
  include Tags
  include CacheUtils
  include BlkTrace

  def setup
    super
    @data_block_size = k(32)
    @cache_blocks = 1024
  end

  #--------------------------------

  def test_clean_data_never_gets_written_back
    nr_blocks = 1234
    s = make_stack(:format => false,
                   :cache_blocks => nr_blocks)
    s.activate_support_devs do
      s.prepare_populated_cache()

      traces, _ = blktrace(s.origin) do
        s.activate_top_level do
          sleep 15
        end
      end

      assert_equal([], traces[0])
    end
  end

  def test_dirty_data_always_gets_written_back
    nr_blocks = 1234
    s = make_stack(:format => false,
                   :cache_blocks => nr_blocks)
    s.activate_support_devs do
      s.prepare_populated_cache(:dirty_percentage => 100)
      traces, _ = blktrace(s.origin) do
        s.activate_top_level do
          sleep 15
        end
      end

      assert_equal(nr_blocks, filter_writes(traces[0]).size)
    end
  end

  private
  def filter_writes(events)
    events.select {|e| e.code.member?(:write)}
  end
end

#----------------------------------------------------------------
