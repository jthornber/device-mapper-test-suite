require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_policy'
require 'dmtest/cache_utils'

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
    block_size = k(64)
    [23, 513, 1023, 4095].each do |nr_blocks|
      s = CacheStack.new(@dm, @metadata_dev, @data_dev, 
                         :format => false,
                         :block_size => block_size,
                         :cache_size => nr_blocks * block_size,
                         :policy => Policy.new('smq'))
      s.activate_support_devs do
        s.prepare_populated_cache(:clean_shutdown => false)
        md1 = dump_metadata(s.md)

        s.activate_top_level {}

        md2 = dump_metadata(s.md)
        assert_equal(md1.mappings, make_mappings_clean(md2.mappings))
      end
    end
  end
end

#----------------------------------------------------------------
