require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_policy'
require 'dmtest/tests/cache/fio_subvolume_scenario'

require 'pp'

#----------------------------------------------------------------

class CacheTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  include FioSubVolumeScenario
  extend TestUtils

  POLICY_NAMES = %w(mq smq)

  def setup
    super
    @data_block_size = meg(1)
  end

  #--------------------------------

  def with_standard_cache(opts = Hash.new, &block)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      block.call(stack.cache)
    end
  end

  #--------------------------------

  tag :cache_target
  def test_dd_cache
    with_standard_cache(:format => true, :data_size => gig(1)) do |cache|
      wipe_device(cache)
    end
  end

  tag :linear_target
  def test_dd_linear
    with_standard_linear(:data_size => gig(1)) do |linear|
      wipe_device(linear)
    end
  end

  #--------------------------------

  tag :cache_target
  def test_fio_cache
    with_standard_cache(:cache_size => meg(512),
                        :format => true,
                        :block_size => 512,
                        :data_size => gig(2),
                        :policy => Policy.new('mq')) do |cache|
      do_fio(cache, :ext4)
    end
  end

  tag :cache_target
  def test_fio_database_funtime
    with_standard_cache(:cache_size => meg(1024 * 2),
                        :format => true,
                        :block_size => 256,
                        :data_size => gig(10),
                        :policy => Policy.new('smq')) do |cache|
      do_fio(cache, :ext4,
             :outfile => AP("fio_dm_cache.out"),
             :cfgfile => LP("tests/cache/database-funtime.fio"))
      pp CacheStatus.new(cache)
    end
  end

  def test_fio_sub_volume
    with_standard_cache(:cache_size => meg(256),
                        :format => true,
                        :block_size => 512,
                        :data_size => gig(4),
                        :policy => Policy.new('mq')) do |cache|

      wait = lambda {wait_for_all_clean(cache)}
      fio_sub_volume_scenario(cache, &wait)
    end
  end

  tag :linear_target
  def test_fio_linear
    with_standard_linear do |linear|
      do_fio(linear, :ext4,
             :outfile => AP("fio_dm_linear.out"),
             :cfgfile => LP("tests/cache/database-funtime.fio"))
    end
  end

  #--------------------------------

  def do_format(dev, fs_type)
    fs = FS::file_system(fs_type, dev)

    report_time("formatting", STDERR) do
      fs.format
    end

    report_time("mount/umount/fsck", STDERR) do
      fs.with_mount('./test_fs', :discard => true) do
      end
    end
  end

  tag :cache_target
  def test_format_cache
    with_standard_cache(:format => true, :policy => Policy.new('mq')) do |cache|
      do_format(cache, :ext4)
    end
  end

  tag :linear_target
  def test_format_linear
    with_standard_linear do |linear|
      do_format(linear, :ext4)
    end
  end

  #--------------------------------

  def do_bonnie(dev, fs_type)
    fs = FS::file_system(fs_type, dev)
    fs.format
    fs.with_mount('./test_fs', :discard => true) do
      Dir.chdir('./test_fs') do
        report_time("bonnie++") do
          ProcessControl::run("bonnie++ -d . -r 0 -u root -s 1024")
        end
      end
    end
  end

  tag :cache_target
  def test_bonnie_cache
    with_standard_cache(:cache_size => meg(256),
                        :format => true,
                        :block_size => 512,
                        :policy => Policy.new('mq')) do |cache|
      do_bonnie(cache, :ext4)
    end
  end

  tag :linear_target
  def test_bonnie_linear
    with_standard_linear do |linear|
      do_bonnie(linear, :ext4)
    end
  end

  #--------------------------------

  def do_git_extract_cache_quick(opts)
    i = opts.fetch(:nr_tags, 5)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      git_prepare(stack.cache, :ext4)
      git_extract(stack.cache, :ext4, TAGS[0..i])
      pp CacheStatus.new(stack.cache)
    end
  end

  tag :cache_target
  def test_git_extract_cache_quick
    do_git_extract_cache_quick(:policy => Policy.new('smq', :migration_threshold => 1024),
                               :cache_size => meg(64),
                               :block_size => 512,
                               :data_size => gig(4))
  end

  def test_git_extract_cache_quick_across_cache_size
    [64, 256, 512, 1024, 1024 + 512, 2048, 2048 + 1024].each do |cache_size|
      report_time("cache size = #{cache_size}, policy = smq", STDERR) do
        do_git_extract_cache_quick(:policy => Policy.new('smq', :migration_threshold => 1024),
                                   :cache_size => meg(cache_size),
                                   :block_size => 512,
                                   :data_size => gig(16))
      end

#      report_time("cache size = #{cache_size}, policy = mq", STDERR) do
#        do_git_extract_cache_quick(:policy => Policy.new('mq', :migration_threshold => 1024),
#                                   :cache_size => meg(cache_size),
#                                   :block_size => 512,
#                                   :data_size => gig(16))
#      end
    end
  end

  def test_git_extract_cache_quick_across_migration_threshold
    [0, 128, 512, 1024, 2048].each do |migration_threshold|
      report_time("migration_threshold = #{migration_threshold}") do
        do_git_extract_cache_quick(:policy => Policy.new('mq',
                                                         :migration_threshold => migration_threshold),
                                   :cache_size => meg(256),
                                   :data_size => gig(2))
      end
    end
  end

  def do_git_extract_only_cache_quick(opts = Hash.new)
    opts = {
      :policy     => opts.fetch(:policy, Policy.new('basic')),
      :cache_size => opts.fetch(:cache_size, meg(256)),
      :data_size  => opts.fetch(:data_size, gig(2))
    }

    with_standard_linear(:data_size => opts[:data_size]) do |origin|
      git_prepare(origin, :ext4)
    end

    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      git_extract(stack.cache, :ext4, TAGS[0..10])
    end
  end

  def git_extract_only_cache_quick(policy_name)
    do_git_extract_only_cache_quick(:policy => Policy.new(policy_name))
  end

  define_tests_across(:git_extract_only_cache_quick, POLICY_NAMES)

  def git_extract_cache_quick(policy_name)
    do_git_extract_cache_quick(:policy => Policy.new(policy_name))
  end

  define_tests_across(:git_extract_cache_quick, POLICY_NAMES)

  def test_git_extract_cache
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, :format => true)
    stack.activate do |stack|
      git_prepare(stack.cache, :ext4)
      git_extract(stack.cache, :ext4)
    end
  end

  def cache_sizing_effect(policy_name)
    cache_sizes = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 1536]
    cache_sizes.each do |size|
      report_time("git_extract_cache_quick", STDERR) do
        do_git_extract_cache_quick(:nr_tags => 1,
                                   :cache_size => meg(size),
                                   :data_size => gig(2),
                                   :policy => Policy.new(policy_name))
      end
    end
  end

  define_tests_across(:cache_sizing_effect, POLICY_NAMES)

  tag :linear_target
  def test_git_extract_linear
    with_standard_linear do |linear|
      git_prepare(linear, :ext4)
      git_extract(linear, :ext4)
    end
  end

  def test_git_extract_linear_quick
    with_standard_linear(:data_size => gig(16)) do |linear|
      git_prepare(linear, :ext4)
      git_extract(linear, :ext4, TAGS[0..5])
    end
  end

  tag :cache_target
  # Checks we can remount an fs
  def test_metadata_persists
    with_standard_cache(:format => true) do |cache|
      fs = FS::file_system(:ext4, cache)
      fs.format
      fs.with_mount('./test_fs') do
        drop_caches
      end
    end

    with_standard_cache do |cache|
      fs = FS::file_system(:ext4, cache)
      fs.with_mount('./test_fs') do
      end
    end
  end

  def test_suspend_resume
    with_standard_cache(:format => true) do |cache|
      git_prepare(cache, :ext4)

      3.times do
        report_time("suspend/resume", STDERR) do
          cache.pause {}
        end
      end
    end
  end

  def test_suspend_resume_under_load
    with_standard_cache(:format => true) do |cache|
      tid1 = Thread.new(cache) do |cache|
        git_prepare(cache, :ext4)
      end

      lock = Mutex.new
      lock.lock
      tid2 = Thread.new(cache) do |cache|
        table = cache.active_table

        while !lock.try_lock
          sleep 1
          cache.pause do
          end

          STDERR.write "."
        end

        STDERR.puts "\nio thread complete"
      end

      tid1.join
      lock.unlock
      tid2.join
    end
  end

  def run_bonnie(dev)
    fs = FS::file_system(:ext4, dev)
    fs.format
    fs.with_mount("./kernel_builds", :discard => true) do
      ProcessControl::run("bonnie++ -d ./kernel_builds -r 0 -u root -s 2048")
    end
  end

  def test_reload_resume_under_load
    with_standard_cache(:format => true) do |cache|
      tid1 = Thread.new(cache) do |cache|
        run_bonnie(cache)
      end

      lock = Mutex.new
      lock.lock
      tid2 = Thread.new(cache) do |cache|
        table = cache.active_table

        while !lock.try_lock
          cache.load(table)
          sleep 1               # window for the two metadata areas to diverge
          cache.pause do
          end

          STDERR.write "."
        end

        STDERR.puts "\nio thread complete"
      end

      tid1.join
      lock.unlock
      tid2.join
    end
  end


  def test_table_reload
    with_standard_cache(:format => true) do |cache|
      table = cache.active_table

      git_prepare(cache, :ext4)

      cache.pause do
        cache.load(table)
      end
    end
  end

  def test_table_reload_changed_policy
    with_standard_cache(:format => true, :policy => Policy.new('mq')) do |cache|
      table = cache.active_table

      tid = Thread.new(cache) do
        git_prepare(cache, :ext4)
      end

      use_mq = false

      while tid.alive?
        sleep 5
        cache.pause do
          table.targets[0].args[5] = use_mq ? 'mq' : 'cleaner'
          cache.load(table)
          use_mq = !use_mq
        end
      end

      tid.join
    end
  end

  def test_cache_grow
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :format => true,
                           :cache_size => meg(16))
    stack.activate do |stack|
      tid = Thread.new(stack.cache) do
        git_prepare(stack.cache, :ext4)
      end

      begin
        [256, 512, 768, 1024].each do |size|
          sleep 10
          stack.resize_ssd(meg(size))
          STDERR.puts "resized to #{size}"
        end
      rescue
        tid.kill
        throw
      ensure
        tid.join
      end
    end
  end

  def test_unknown_policy_fails
    assert_raise(ExitError) do
      with_standard_cache(:format => true,
                          :policy => Policy.new('time_traveller')) do |cache|
      end
    end
  end

  #--------------------------------

  def test_cleaner_policy
    with_standard_cache(:format => true) do |cache|
      git_prepare(cache, :ext4)

      cache.pause do
        table = cache.active_table
        table.targets[0].args[5] = 'cleaner'
        cache.load(table)
      end

      wait_for_all_clean(cache)

      cache.pause do
        table = cache.active_table
        table.targets[0].args[5] = 'mq'
        cache.load(table)
      end

      status = CacheStatus.new(cache)
      assert_equal(0, status.nr_dirty)
    end

    # We should be able to use the origin directly now
    with_standard_linear do |origin|
      fs = FS::file_system(:ext4, origin)
      fs.with_mount('./kernel_builds', :discard => true) do
        # triggers fsck
      end
    end
  end

  def test_construct_cache
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, :format => true)
    stack.activate do |stack|
    end
  end

  # We know the kernel uses the same bio for both branches of the
  # writethrough.  To double check the mapping we offset the origin
  # device.
  def test_writethrough
    data_size = dev_size(@data_dev)
    size = gig(2)
    offset = 512 + 128

    raise RuntimeError, "data device too small" unless data_size >= size + offset

    tvm = TinyVolumeManager::VM.new
    tvm.add_allocation_volume(@data_dev)
    tvm.add_volume(linear_vol('offset_volume', offset))
    tvm.add_volume(linear_vol('origin_dev', size))

    # paranoia
    with_dev(tvm.table('offset_volume')) do |offset|
      wipe_device(offset)
    end

    # wipe the origin to ensure we don't accidentally have the same
    # data on it.
    with_dev(tvm.table('origin_dev')) do |origin|
      wipe_device(origin)

      # format and set up a git repo on the cache
      stack = CacheStack.new(@dm, @metadata_dev, origin,
                             :format => true,
                             :io_mode => :writethrough,
                             :data_size => size)
      stack.activate do |stack|
        git_prepare(stack.cache, :ext4)
      end

      # we do an extract to check the cache is ok
      stack.activate do |stack|
        git_extract(stack.cache, :ext4, TAGS[0..1])
      end
    end

    # origin should have all data
    with_dev(tvm.table('origin_dev')) do |origin|
      git_extract(origin, :ext4, TAGS[1..2])
    end
  end

  def test_origin_grow
    # format and set up a git repo on the cache
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :format => true,
                           :io_mode => :writethrough,
                           :data_size => gig(2))
    stack.activate do |stack|
      git_prepare(stack.cache, :ext4)
      stack.resize_origin(gig(3))
      git_extract(stack.cache, :ext4, TAGS[0..1])
    end
  end

  def test_origin_shrink
    # format and set up a git repo on the cache
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :format => true,
                           :io_mode => :writethrough,
                           :data_size => gig(3))
    stack.activate do |stack|
      git_prepare(stack.cache, :ext4)
      stack.resize_origin(gig(2))
      git_extract(stack.cache, :ext4, TAGS[0..1])
    end
  end

  def test_status
    opts = Hash.new
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      status = CacheStatus.new(stack.cache)

      # verify that the "default" policy maps to "mq"
      assert_equal(status.policy_name, 'mq')

      pp status
    end
  end

  def test_table
    opts = Hash.new
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      assert(stack.cache.table =~ /0 \d+ cache \d+:\d+ \d+:\d+ \d+:\d+ 512 0 default 0/)
    end
  end

  def test_message
    opts = Hash.new
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      stack.cache.message(0, "migration_threshold 12345")
      stack.cache.message(0, "random_threshold 4321")
      status = CacheStatus.new(stack.cache)

      # FIXME: these asserts don't work!
      assert(status.core_args.assoc('migration_threshold'), '12345')
      assert(status.policy_args.assoc('random_threshold'), '4321')
    end
  end
end

#----------------------------------------------------------------
