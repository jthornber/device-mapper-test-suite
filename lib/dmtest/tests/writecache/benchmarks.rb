require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/writecache-stack'
require 'dmtest/tests/cache/fio_subvolume_scenario'
require 'dmtest/pattern_stomper'
require 'pp'

#----------------------------------------------------------------

# Tests for comparing mq against smq.  This will probably become
# obsolete at some point since I'm intending smq to replace mq.
class WriteCacheBenchmarks < ThinpTestCase
  include GitExtract
  include Utils
  include DiskUnits
  include FioSubVolumeScenario
  extend TestUtils

  def setup
    super
  end

  #--------------------------------

  def with_standard_cache(opts = Hash.new, &block)
    stack = WriteCacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      block.call(stack.cache)
    end
  end

  #--------------------------------

  define_test :validate_cache do
    opts = {:cache_size => meg(512),
            :data_size => gig(2)}
    stack = WriteCacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate_support_devs do |stack|
      origin_stomper = PatternStomper.new(stack.origin.path, k(32), :needs_zero => true)
      origin_stomper.stamp(20)

      cache_stomper = nil
      
      stack.activate_top_level do |stack|
        cache_stomper = origin_stomper.fork(stack.cache.path)
        cache_stomper.verify(0, 1)
	cache_stomper.stamp(20)

        origin_stomper = cache_stomper.fork(stack.origin.path)
        stack.wait_until_clean
      end

      origin_stomper.verify(0, 2)
    end
  end

  #--------------------------------

  define_test :fio_cache do
    with_standard_cache(:cache_size => meg(512),
                        :format => true,
                        :data_size => gig(2)) do |cache|
      do_fio(cache, :ext4)
    end
  end

  #--------------------------------

  def do_fio_database(opts)
    with_standard_cache(opts) do |cache|
      do_fio(cache, :ext4,
             :outfile => AP("fio_dm_writecache.out"),
             :cfgfile => LP("tests/cache/database-funtime.fio"))
    end
  end

  def do_fio_database_across_cache_size()
    [128, 256, 512, 1024, 2048, 4096, 8192, 8192 + 1024].each do |cache_size|
      report_time("cache size = #{cache_size}", STDERR) do
        do_fio_database(:cache_size => meg(cache_size),
                        :data_size => gig(16))
      end
    end
  end

  define_test :fio_database_across_cache_size do
    do_fio_database_across_cache_size()
  end

  #--------------------------------
  
  def do_git_extract_cache(opts)
    i = opts.fetch(:nr_tags, 5)
    with_standard_cache(opts) do |cache|
      git_prepare(cache, :ext4)
      git_extract(cache, :ext4, TAGS[0..i])
    end
  end

  def do_git_extract_cache_quick_across_cache_size()
    [64, 256, 512, 1024, 1024 + 512, 2048, 4096].each do |cache_size|
      report_time("cache size = #{cache_size}", STDERR) do
        do_git_extract_cache(:cache_size => meg(cache_size),
                             :data_size => gig(16),
                             :nr_tags => 20)
      end
    end
  end

  define_test :git_extract_cache_quick_across_cache_size do
    do_git_extract_cache_quick_across_cache_size()
  end

  #--------------------------------

  # FIXME: broken
  def do_git_extract_only(opts)
    i = opts.fetch(:nr_tags, 5)

    with_standard_linear(:data_size => opts[:data_size]) do |origin|
      git_prepare(origin, :ext4)

      stack = WriteCacheStack.new(@dm, @metadata_dev, origin, opts)
      stack.activate do |stack|
        git_extract_each(stack.cache, :ext4, TAGS[0..i]) do
        end
      end
    end
  end

  define_test :git_extract_only_across_cache_size do
     [256, 512, 1024, 1024 + 512, 2048, 4096].each do |cache_size|
      report_time("cache size = #{cache_size}", STDERR) do
        do_git_extract_only(:cache_size => meg(cache_size),
                            :data_size => gig(16),
                            :nr_tags => 20)
      end
    end 
  end
end
