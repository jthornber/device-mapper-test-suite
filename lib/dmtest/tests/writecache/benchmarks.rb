require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/writecache-stack'
require 'dmtest/fio-benchmark'
require 'dmtest/pattern_stomper'
require 'pp'

#----------------------------------------------------------------

class WriteCacheBenchmarks < ThinpTestCase
  include GitExtract
  include Utils
  include DiskUnits
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

  def do_fio_database_across_cache_size(read_percent)
    [128, 256, 512, 1024, 2048, 4096, 8192].each do |cache_size|
      report_time("cache size = #{cache_size}", STDERR) do
        stack = WriteCacheStack.new(@dm, @metadata_dev, @data_dev,
                                    :cache_size => meg(cache_size),
                                    :data_size => gig(16))
        fio = FioBenchmark::new(stack,
                                :nr_jobs => 4,
                                :size_m => 256,
                                :read_percent => read_percent)
        fio.run
      end
    end
  end
  
  define_test :fio_database_across_cache_size_r100 do
    do_fio_database_across_cache_size(100)
  end

  define_test :fio_database_across_cache_size_r50 do
    do_fio_database_across_cache_size(50)
  end

  define_test :fio_database_across_cache_size_r0 do
    do_fio_database_across_cache_size(0)
  end

  #--------------------------------
  
  def do_git_extract_cache(opts)
    i = opts.fetch(:nr_tags, 0)
    with_standard_cache(opts) do |cache|
      git_prepare(cache, :ext4)
      git_extract(cache, :ext4, TAGS[0..i]) if i > 0
    end
  end

  def do_git_extract_cache_quick(cache_size, nr_tags)
      report_time("cache size = #{cache_size}", STDERR) do
        do_git_extract_cache(:cache_size => meg(cache_size),
                             :data_size => gig(16),
                             :nr_tags => nr_tags)
      end
  end

  define_test :git_extract_cache_quick_across_cache_size do
    [64, 256, 512, 1024, 1024 + 512, 2048, 4096, 8192].each do |cache_size|
      do_git_extract_cache_quick(cache_size, 20)
    end
  end

  define_test :git_extract_cache_quick_64M do
    do_git_extract_cache_quick(64, 20)
  end

  define_test :git_prepare_cache_quick_64M do
    do_git_extract_cache_quick(64, 0)
  end

  #--------------------------------

  def do_git_extract_only(opts)
    i = opts.fetch(:nr_tags, 5)

    stack = WriteCacheStack.new(@dm, @metadata_dev, @data_dev, opts)

    stack.activate_support_devs do |stack|
      git_prepare(stack.origin, :ext4)
      stack.activate_top_level do |stack|
        git_extract_each(stack.cache, :ext4, TAGS[0..i]) {}
        git_extract_each(stack.cache, :ext4, TAGS[0..i]) {}
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

  #--------------------------------

  define_test :dd_hotspot do
    stack = WriteCacheStack.new(@dm, @metadata_dev, @data_dev,
                                :cache_size => gig(8),
                                :data_size => gig(16))
    stack.activate do
      32.times do |n|
        report_time("dd pass #{n}", STDERR) do
          wipe_device(stack.cache, gig(1))
        end
      end
    end
  end
end
