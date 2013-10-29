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

class NoCleanShutdownTests < ThinpTestCase
  include GitExtract
  include Tags
  include CacheUtils

  def setup
    super
    @data_block_size = k(32)
    @cache_blocks = 1024
  end

  #--------------------------------

  def test_no_resize_retains_mappings_all_clean
    [23, 513, 1023, 4095].each do |nr_blocks|
      prepare_populated_cache(:cache_blocks => nr_blocks,
                              :clean_shutdown => false)

      s = make_stack(:format => false,
                     :cache_blocks => nr_blocks)
      s.activate_support_devs do
        md1 = dump_metadata(s.md)

        s.activate_top_level {}

        md2 = dump_metadata(s.md)
        assert_equal(md1.mappings, md2.mappings)
      end
    end
  end
end

#----------------------------------------------------------------
