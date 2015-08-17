require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/pattern_stomper'
require 'dmtest/test-utils'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/cache_policy'
require 'dmtest/thinp-test'
require 'dmtest/tvm.rb'
require 'dmtest/utils'

require 'thinp_xml/cache_xml'

#----------------------------------------------------------------

class InvalidateCBlocksTests < ThinpTestCase
  include GitExtract
  include CacheUtils
  extend TestUtils

  def setup
    super
    @data_block_size = k(64)
    @cache_blocks = 10
    @nr_blocks = 100
    @nr_snapshots = 20
  end

  def check_mapped_single(md, n)
    found = false
    md.mappings.each do |m|
      if m.cache_block == n
        found = true
      end
    end

    found.should == true
  end

  def check_mapped_range(md, r)
    r.each do |n|
      check_mapped_single(md, n)
    end
  end

  def check_mapped(md, ranges)
    ranges.each do |rs|
      if rs.kind_of?(Range)
        check_mapped_range(md, rs)
      else
        check_mapped_single(md, rs)
      end
    end
  end

  def check_unmapped_single(md, n)
    md.mappings.each do |m|
      m.cache_block.should_not == n
    end
  end

  def check_unmapped_range(md, r)
    r.each do |n|
      check_unmapped_single(md, n)
    end
  end

  def check_unmapped(md, ranges)
    ranges.each do |rs|
      if rs.kind_of?(Range)
        check_unmapped_range(md, rs)
      else
        check_unmapped_single(md, rs)
      end
    end
  end

  def bad_range(str)
    s = make_stack(:format => false,
                   :block_size => @data_block_size,
                   :cache_blocks => @nr_blocks,
                   :io_mode => :passthrough)
    expect do
      s.activate do
        s.cache.message(0, "invalidate_cblocks #{str}")
      end
    end.to raise_error
  end

  def cant_be_in_io_mode(mode)
    s = make_stack(:format => true,
                   :block_size => @data_block_size,
                   :cache_blocks => @nr_blocks,
                   :io_mode => mode)
    s.activate do
      expect do
        s.cache.message(0, "invalidate_cblocks 0-#{@nr_blocks}")
      end.to raise_error
    end
  end

  #--------------------------------

  define_test :must_be_in_passthrough_mode do
    cant_be_in_io_mode(:writeback)
    cant_be_in_io_mode(:writethrough)
  end

  define_test :invalidating_all_cblocks_in_an_empty_cache do
    s = make_stack(:format => true,
                   :block_size => @data_block_size,
                   :cache_blocks => @nr_blocks,
                   :io_mode => :passthrough)
    s.activate_support_devs do
      s.activate_top_level do
        s.cache.message(0, "invalidate_cblocks 0-#{@nr_blocks}")
      end

      md = dump_metadata(s.md)
      md.mappings.length.should == 0
    end
  end

  define_test :invalidating_all_cblocks_in_a_full_cache do
    s = make_stack(:format => false,
                   :block_size => @data_block_size,
                   :cache_blocks => @nr_blocks,
                   :io_mode => :passthrough)
    s.activate_support_devs do
      s.prepare_populated_cache(:dirty_percentage => 0);

      s.activate_top_level do
        s.cache.message(0, "invalidate_cblocks 0-#{@nr_blocks}")
      end

      md = dump_metadata(s.md)
      md.mappings.length.should == 0
    end
  end

  define_test :invalidating_multiple_args do
    s = make_stack(:format => false,
                   :block_size => @data_block_size,
                   :cache_blocks => @nr_blocks,
                   :io_mode => :passthrough)
    s.activate_support_devs do
      s.prepare_populated_cache(:dirty_percentage => 0)
      s.activate_top_level do
        s.cache.message(0, "invalidate_cblocks 0 5 11 50-60 91-99")
      end

      md = dump_metadata(s.md)
      check_unmapped(md, [0, 5, 11, 50..59, 91..98])
      check_mapped(md, [1..4, 6..10, 12..49, 60..90, 99])
    end
  end

  define_test :out_of_bounds_range do
    s = make_stack(:format => false,
                   :block_size => @data_block_size,
                   :cache_blocks => @nr_blocks,
                   :io_mode => :passthrough)
    expect do
      s.activate do
        s.cache.message(0, "invalidate_cblocks 50-500")
      end
    end.to raise_error
  end

  define_test :badly_formed_range do
    bad_range('50..60')
    bad_range('50--60')
    bad_range('-60')
    bad_range('50-')
    bad_range('fred')
  end
end

#----------------------------------------------------------------
