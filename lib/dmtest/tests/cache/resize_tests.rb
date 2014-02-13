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

class ResizeTests < ThinpTestCase
  include GitExtract
  include Tags
  include CacheUtils

  def setup
    super
    @data_block_size = k(32)
    @cache_blocks = 1024
  end

  def setup_metadata(nr_blocks)
    s = make_stack(:format => false,
                   :cache_blocks => nr_blocks)
    s.activate_support_devs do
      s.prepare_populated_cache
      md = dump_metadata(s.md)
      md.superblock.nr_cache_blocks.should == nr_blocks
      md
    end
  end

  def activate_kernel(nr_blocks)
    s = make_stack(:format => false,
                   :cache_blocks => nr_blocks,
                   :policy => Policy.new(:mq, :migration_threshold => 0))
    s.activate_support_devs do
      s.activate_top_level {}
      dump_metadata(s.md)
    end
  end

  #--------------------------------

  def test_no_resize_retains_mappings_all_clean
    [23, 513, 1023, 4095].each do |nr_blocks|
      s = make_stack(:format => false,
                     :cache_blocks => nr_blocks)
      s.activate_support_devs do
        s.prepare_populated_cache()
        md1 = dump_metadata(s.md)

        s.activate_top_level {}

        md2 = dump_metadata(s.md)
        assert_equal(md1.mappings, md2.mappings)
      end
    end
  end

  def test_no_resize_retains_mappings_all_dirty
    [23, 513, 1023, 4095].each do |nr_blocks|
      s = make_stack(:format => false,
                     :cache_blocks => nr_blocks)
      s.activate_support_devs do
        s.prepare_populated_cache(:dirty_percentage => 100)
        md1 = dump_metadata(s.md)

        s.activate_top_level do
        end

        md2 = dump_metadata(s.md)

        # some mappings may now be clean since there's a background
        # writeback task.  So we force them all to be dirty
        assert_equal(md1.mappings, make_mappings_dirty(md2.mappings))
      end
    end
  end

  #--------------------------------

  def grow_test(nr_blocks)
    md1 = setup_metadata(nr_blocks)
    new_nr_blocks = nr_blocks + 5678
    md2 = activate_kernel(new_nr_blocks)
    md2.mappings.should == md1.mappings
    md2.superblock.nr_cache_blocks.should == new_nr_blocks
  end

  def test_metadata_can_grow
    [23, 513, 1023, 4095].each {|nr_blocks| grow_test(nr_blocks)}
  end

  #--------------------------------

  def shrink_test(nr_blocks)
    md1 = setup_metadata(nr_blocks)
    new_nr_blocks = nr_blocks / 2
    md2 = activate_kernel(new_nr_blocks)
    md2.mappings.should == md1.mappings[0..new_nr_blocks - 1]
    md2.superblock.nr_cache_blocks.should == new_nr_blocks
  end

  def test_metadata_can_shrink
    [23, 345, 513, 876, 1023, 2345, 4095].each {|nr_blocks| shrink_test(nr_blocks)}
  end
end

#----------------------------------------------------------------
