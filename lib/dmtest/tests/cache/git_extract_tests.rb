require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_policy'
require 'dmtest/tests/cache/fio_subvolume_scenario'
require 'dmtest/tests/cache/pool_cache_stack'
require 'pp'

#----------------------------------------------------------------

class GitExtractTests < ThinpTestCase
  include GitExtract
  include Utils
  include DiskUnits
  extend TestUtils

  POLICY_NAMES = %w(mq smq)
  METADATA_VERSIONS = [1, 2]
  IO_MODES = [:writeback, :writethrough]

  def setup
    super
    @data_block_size = meg(1)
  end

  #--------------------------------

  def do_git_extract_cache(opts)
    i = opts.fetch(:nr_tags, 5)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      git_prepare(stack.cache, :ext4)

      1.times do
        git_extract(stack.cache, :ext4, TAGS[0..i])
        pp CacheStatus.new(stack.cache)
      end
    end
  end

  def git_extract_cache_quick(policy, version, io_mode)
    do_git_extract_cache(:policy => Policy.new(policy, :migration_threshold => 1024),
                         :cache_size => meg(1024),
                         :block_size => k(32),
                         :data_size => gig(16),
                         :nr_tags => 5,
			 :io_mode => io_mode,
                         :metadata_version => version)
  end

  define_tests_across(:git_extract_cache_quick,
		      POLICY_NAMES, METADATA_VERSIONS, IO_MODES)

  def git_extract_cache_long(policy, version)
    do_git_extract_cache(:policy => Policy.new(policy, :migration_threshold => 1024),
                         :cache_size => meg(1024),
                         :block_size => k(32),
                         :data_size => gig(16),
                         :nr_tags => 20,
                         :metadata_version => version)
  end

  define_tests_across(:git_extract_cache_long, POLICY_NAMES, METADATA_VERSIONS)

  def git_extract_cache_across_cache_size(policy, version)
    [64, 256, 512, 1024, 1024 + 512, 2048, 2048 + 1024].each do |cache_size|
      report_time("cache size = #{cache_size}, policy = #{policy}", STDERR) do
        do_git_extract_cache(:policy => Policy.new(policy, :migration_threshold => 1024),
                             :cache_size => meg(cache_size),
                             :block_size => k(32),
                             :data_size => gig(16),
                             :metadata_version => version)
      end
    end
  end

  define_tests_across(:git_extract_cache_across_cache_size, POLICY_NAMES, METADATA_VERSIONS)

  #--------------------------------

  def git_extract_only(opts)
    i = opts.fetch(:nr_tags, 5)

    with_standard_linear(:data_size => opts[:data_size]) do |origin|
      git_prepare(origin, :ext4)

      stack = CacheStack.new(@dm, @metadata_dev, origin, opts)
      stack.activate do |stack|
        git_extract_each(stack.cache, :ext4, TAGS[0..i])
      end
    end
  end

  def git_extract_only_quick(policy, version)
    git_extract_only(:policy => Policy.new(policy, :migration_threshold => 1024),
                     :cache_size => meg(512),
                     :block_size => k(32),
                     :data_size => gig(16),
                     :metadata_version => version)
  end

  define_tests_across(:git_extract_only_quick, POLICY_NAMES, METADATA_VERSIONS)

  #--------------------------------

  def git_extract_only_long(policy, version)
    git_extract_only(:policy => Policy.new(policy, :migration_threshold => 1024),
                     :cache_size => meg(3072),
                     :block_size => k(32),
                     :data_size => gig(16),
                     :nr_tags => 20,
                     :metadata_version => version)
  end

  define_tests_across(:git_extract_only_long, POLICY_NAMES, METADATA_VERSIONS)

  #--------------------------------

  def git_extract_only_across_cache_size(policy_name, version)
    [64, 256, 512, 1024, 1024 + 512, 2048, 2048 + 1024].each do |cache_size|
      report_time("cache size = #{cache_size}, policy = #{policy_name}", STDERR) do
        git_extract_only(:policy => Policy.new(policy_name, :migration_threshold => 1024),
                         :cache_size => meg(cache_size),
                         :block_size => 64,
                         :data_size => gig(16),
                         :metadata_version => version)
      end
    end
  end

  define_tests_across(:git_extract_only_across_cache_size, POLICY_NAMES, METADATA_VERSIONS)

  #--------------------------------

  define_test :git_extract_linear_quick do
    with_standard_linear(:data_size => gig(16)) do |linear|
      git_prepare(linear, :ext4)
      git_extract(linear, :ext4, TAGS[0..5])
    end
  end

  define_test :git_extract_linear_long do
    with_standard_linear(:data_size => gig(16)) do |origin|
      git_prepare(origin, :ext4)
      git_extract(origin, :ext4, TAGS[0..20])
    end
  end

  #--------------------------------

  def thin_on_cache(policy, version)
    data_size = gig(64)

    stack = PoolCacheStack.new(@dm, @metadata_dev, @data_dev,
                               { :policy => Policy.new(policy, :migration_threshold => 1024),
                                 :cache_size => meg(3072),
                                 :block_size => k(32),
                                 :data_size => data_size,
                                 :format => true,
                                 :metadata_version => version
                               },
                               {
                                 :data_size => data_size,
                                 :block_size => meg(4),
                                 :zero => false,
                                 :format => true,
                                 :discard => true,
                                 :discard_passdown => true
                               })
    stack.activate do |pool|
      with_new_thin(pool, gig(16), 0) do |thin|
        git_prepare(thin, :ext4)

        with_new_snap(pool, gig(16), 1, 0, thin) do |snap|
          git_extract(thin, :ext4, TAGS[0..5])
          git_extract(snap, :ext4, TAGS[0..5])
        end
      end
    end
  end

  define_tests_across(:thin_on_cache, POLICY_NAMES, METADATA_VERSIONS)

  #--------------------------------

  def cached_data_device_alternating_thins(policy_name, version)
    data_size = gig(32)

    stack = PoolCacheStack.new(@dm, @metadata_dev, @data_dev,
                               { :policy => Policy.new(policy_name, :migration_threshold => 1024),
                                 :cache_size => meg(1024),
                                 :block_size => k(32),
                                 :data_size => data_size,
                                 :format => true,
                                 :metadata_version => version
                               },
                               {
                                 :data_size => data_size,
                                 :block_size => meg(4),
                                 :zero => false,
                                 :format => true,
                                 :discard => true,
                                 :discard_passdown => true
                               })
    stack.activate do |pool|
      with_new_thins(pool, gig(16), 0, 1) do |thin1, thin2|
        git_prepare_no_discard(thin1, :ext4)
        git_prepare_no_discard(thin2, :ext4)

        10.times do |n|
          report_time("#{policy_name}, extract to thin1 - iteration #{n}", STDERR) do
            git_extract(thin1, :ext4, TAGS[0..5])
            pp CacheStatus.new(stack.cache)
          end

          report_time("#{policy_name}, extract to thin2 - iteration #{n}", STDERR) do
            git_extract(thin2, :ext4, TAGS[0..5])
            pp CacheStatus.new(stack.cache)
          end
        end
      end
    end
  end

  define_tests_across(:cached_data_device_alternating_thins, POLICY_NAMES, METADATA_VERSIONS)

  #--------------------------------

  def cache_on_thin(version)
    cache_size = meg(1024)

    tvm = TinyVolumeManager::VM.new
    tvm.add_allocation_volume(@metadata_dev)
    tvm.add_volume(linear_vol('pool_md', meg(64)))
    tvm.add_volume(linear_vol('cache_space', meg(64) + cache_size))

    with_devs(tvm.table('pool_md'),
              tvm.table('cache_space')) do |pool_md, cache_space|
      pstack = PoolStack.new(@dm, @data_dev, pool_md, :zero => false, :format => true)
      pstack.activate() do |pool|
        with_new_thin(pool, gig(16), 0) do |thin|
          cstack = CacheStack.new(@dm, cache_space, thin,
                                  :policy => Policy.new('smq', :migration_threshold => 1024),
                                  :cache_size => cache_size,
                                  :block_size => k(32),
                                  :format => true,
                                  :metadata_version => version)
          cstack.activate do |cs|
            git_prepare(cs.cache, :ext4)
            git_extract(cs.cache, :ext4, TAGS[0..5])
          end
        end
      end
    end
  end

  define_tests_across(:cache_on_thin, METADATA_VERSIONS)

  #--------------------------------

  def alternate_between_mq_and_smq(version)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :policy => Policy.new('mq', :migration_threshold => 1024),
                           :cache_size => meg(1024),
                           :block_size => k(32),
                           :data_size => gig(16),
                           :metadata_version => version)

    stack.activate do |stack|
      git_prepare(stack.cache, :ext4)

      smq = false
      git_extract_each(stack.cache, :ext4, TAGS[0..10]) do

        pp CacheStatus.new(stack.cache)

        stack.cache.pause do
          if smq
            STDERR.puts "switching to mq"
            stack.change_policy(Policy.new('mq', :migration_threshold => 1024))
          else
            STDERR.puts "switching to smq"
            stack.change_policy(Policy.new('smq', :migration_threshold => 1024))
          end

          stack.reload_cache
        end

        smq = !smq
      end
    end
  end

  define_tests_across(:alternate_between_mq_and_smq, METADATA_VERSIONS)
end

#----------------------------------------------------------------
