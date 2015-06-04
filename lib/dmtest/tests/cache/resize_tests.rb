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
require 'dmtest/test-utils'

require 'thinp_xml/cache_xml'

#----------------------------------------------------------------

class ResizeTests < ThinpTestCase
  include GitExtract
  include Tags
  include CacheUtils
  extend TestUtils

  POLICY_NAMES = %w(mq smq)

  def setup
    super
    @data_block_size = k(64)
    @cache_blocks = 1024
  end

  def setup_metadata(nr_blocks)
    s = CacheStack.new(@dm, @metadata_dev, @data_dev,
                       :format => false,
                       :block_size => @data_block_size,
                       :cache_size => nr_blocks * @data_block_size,
                       :policy => Policy.new('smq', :migration_threshold => 1024))
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

  def mk_stack(policy, nr_blocks)
    CacheStack.new(@dm, @metadata_dev, @data_dev,
                   :format => false,
                   :block_size => @data_block_size,
                   :cache_size => nr_blocks * @data_block_size,
                   :policy => Policy.new(policy,
                                         :migration_threshold => 0))
  end

  def no_resize_retains_mappings_all_clean(policy)
    [23, 513, 1023, 4095].each do |nr_blocks|
      s = mk_stack(policy, nr_blocks)
      s.activate_support_devs do
        s.prepare_populated_cache()
        md1 = dump_metadata(s.md)

        s.activate_top_level {}

        md2 = dump_metadata(s.md)
        assert_equal(md1.mappings, md2.mappings)
      end
    end
  end

  define_tests_across(:no_resize_retains_mappings_all_clean, POLICY_NAMES)

  #--------------------------------

  def no_resize_retains_mappings_all_dirty(policy)
    [23, 513, 1023, 4095].each do |nr_blocks|
      s = mk_stack(policy, nr_blocks)
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

  define_tests_across(:no_resize_retains_mappings_all_dirty, POLICY_NAMES)

  #--------------------------------

  def error_table(nr_sectors)
    Table.new(ErrorTarget.new(nr_sectors))
  end

  # FIXME: these tests currently need manual inspection of kernel
  # pr_alerts to confirm they're working.  Need to automate by adding
  # discard bitset support to the tools.

  # We need to make sure we test various different discard bitset
  # sizes.  To make the origin big enough we use an error target.
  def resize_origin_with_teardown(policy)
    nr_blocks = 1024
    osize1 = gig(4)
    osize2 = meg(128)

    s = CacheStack.new(@dm, @metadata_dev, @data_dev,
                       :format => true,
                       :block_size => @data_block_size,
                       :cache_size => nr_blocks * @data_block_size,
                       :data_size => osize1,
                       :policy => Policy.new(policy, :migration_threshold => 0))
    s.activate do
      s.cache.discard(0, meg(64))
      s.cache.discard(meg(96), meg(64))
    end

    s = CacheStack.new(@dm, @metadata_dev, @data_dev,
                       :format => false,
                       :block_size => @data_block_size,
                       :cache_size => nr_blocks * @data_block_size,
                       :data_size => osize2,
                       :policy => Policy.new(policy, :migration_threshold => 0))
    s.activate do
    end
  end

  define_tests_across(:resize_origin_with_teardown, POLICY_NAMES)

  #--------------------------------
  
  def resize_origin_with_reload(policy)
    osize1 = meg(128)
    osize2 = gig(4)
    nr_blocks = 1024

      s = CacheStack.new(@dm, @metadata_dev, @data_dev,
                         :format => true,
                         :block_size => @data_block_size,
                         :cache_size => nr_blocks * @data_block_size,
                         :data_size => osize1,
                         :policy => Policy.new(policy, :migration_threshold => 0))
    s.activate do
      s.cache.discard(0, meg(64))
      s.cache.discard(meg(96), meg(32))
      s.resize_origin(osize2)
    end
  end

  define_tests_across(:resize_origin_with_reload, POLICY_NAMES)

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
