require 'config'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'

require 'pp'

#----------------------------------------------------------------

class TestCases
  attr_reader :params

  def initialize
    # FIXME: enough variations?
    # _# suffixes to policy option keys (eg. :hits_2 as oposed to :hits) are
    # being used to deploy an option multiple times
    @params = [
    # [ should_fail, feature_option_hash, policy_option_hash ]
      [ false, {}, {} ],
      [ false, {}, { :sequential_threshold => 234 } ],
      [ false, { :io_mode => 'writethrough' }, { :sequential_threshold => 234 } ],
      [ false, {}, { :random_threshold => 16 } ],
      [ false, { :io_mode => 'writeback' }, { :random_threshold => 16 } ],
      [ false, { :io_mode => 'writethrough' } , { :random_threshold => 16 } ],
      [ false, {}, { :random_threshold => 16, :sequential_threshold => 234 } ],
      [ false, { :io_mode => 'writeback' }, { :sequential_threshold => 234, :random_threshold => 16 } ],
      [ false, { :io_mode => 'writethrough' }, { :sequential_threshold => 234, :random_threshold => 16 } ],
      [ false, {}, { :multiqueue_timeout => 3333 } ],
      [ false, { :io_mode => 'writeback' }, { :multiqueue_timeout => 3333 } ],
      [ false, { :io_mode => 'writethrough'} , { :multiqueue_timeout => 3333 } ],
      [ false, {}, { :multiqueue_timeout => 3333, :sequential_threshold => 234 } ],
      [ false, {}, { :sequential_threshold => 234, :multiqueue_timeout => 3333 } ],
      [ false, {}, { :multiqueue_timeout => 3333, :random_threshold => 16 } ],
      [ false, {}, { :random_threshold => 16, :multiqueue_timeout => 3333 } ],
      [ false, {}, { :sequential_threshold => 234, :random_threshold => 16, :multiqueue_timeout => 3333 } ],
      [ false, {}, { :random_threshold => 16, :multiqueue_timeout => 3333, :sequential_threshold => 234 } ],
      [ false, {}, { :hits => 0 } ],
      [ false, {}, { :hits => 1 } ],
      [ false, {}, { :sequential_threshold => 234, :hits => 0 } ],
      [ false, {}, { :hits => 0, :sequential_threshold => 234 } ],
      [ false, {}, { :sequential_threshold => 234, :hits => 1 } ],
      [ false, {}, { :hits => 1, :sequential_threshold => 234 } ],
      [ false, {}, { :random_threshold => 16, :hits => 0 } ],
      [ false, {}, { :hits => 0, :random_threshold => 16 } ],
      [ false, {}, { :random_threshold => 16, :hits => 1 } ],
      [ false, {}, { :hits => 1, :random_threshold => 16 } ],
      [ false, { :io_mode => 'writeback'} , { :sequential_threshold => 234, :random_threshold => 16, :hits => 0 } ],
      [ false, {}, { :sequential_threshold => 234, :random_threshold => 16, :hits => 0 } ],
      [ false, {}, { :random_threshold => 16, :hits => 0, :sequential_threshold => 234 } ],
      [ false, {}, { :hits => 0, :sequential_threshold => 234, :random_threshold => 16 } ],
      [ false, {}, { :sequential_threshold => 234, :random_threshold => 16, :hits => 1 } ],
      [ false, {}, { :random_threshold => 16, :hits => 1, :sequential_threshold => 234 } ],
      [ false, {}, { :hits => 1, :sequential_threshold => 234, :random_threshold => 16 } ],

      [ true,  {}, { :sequential_threshold_1 => 234, :sequential_threshold_2 => 234 } ],
      [ true,  {}, { :random_threshold_1 => 16, :random_threshold_2 => 32 } ],
      [ true,  { :io_mode => 'writefoobar' }, { :sequential_threshold_1 => 234, :sequential_threshold_2 => 234 } ],
      [ true,  {}, { :hits_1 => 1, :hits_2 => 1 } ],
      [ true,  {}, { :hits => -1 } ],
      [ true,  {}, { :hits => 3 } ],
      [ true,  {}, { :bogus_huddel_key => 3 } ],
      [ true,  {}, { :sequential_threshold => -1 } ],
      [ true,  {}, { :random_threshold => -1 } ]
    ]
  end

  def add_case(should_fail, feature_opts = Hash.new, policy_opts = Hash.new)
    @params += [should_fail, feature_opts, policy_opts]
  end

  def del_case(should_fail, feature_opts = Hash.new, policy_opts = Hash.new)
    @params.delete_at(i) if (i = find_case(should_fail, feature_opts, policy_opts))
  end

  def find_case(should_fail, feature_opts = Hash.new, policy_opts = Hash.new)
    @params.index([should_fail, feature_opts, policy_opts])
  end
end

class Policy
  attr_accessor :name, :opts

  def initialize(name, opts = Hash.new)
    @name = name
    @opts = opts

    @mq_module_policies = ['default', 'mq']
    @basic_module_policies = ['basic', 'multiqueue', 'multiqueue_ws', 'q2', 'twoqueue',
                              'fifo', 'filo', 'lfu', 'mfu', 'lfu_ws', 'mfu_ws', 'lru',
                              'mru', 'noop', 'random', 'dumb']
    @threshold_options = ['sequential_threshold', 'random_threshold']
    @basic_module_options = ['multiqueue_timeout', 'hits']
  end

  def is_valid_policy_name(name = @name)
    (@mq_module_policies + @basic_module_policies).include?(name)
  end

  def is_basic_module(name = @name)
    @basic_module_policies.include?(@name)
  end

  def is_basic_multiqueue(name = @name)
    ['basic', 'multiqueue', 'multiqueue_ws'].include?(@name)
  end

  def is_valid_policy_arg(name)
    options = @threshold_options
    options += @basic_module_options if is_basic_module(@name)
    options.include?(name)
  end

  def all_options
    @threshold_options + @basic_module_options
  end

  def run_test(policy_opts = @opts)
    if is_basic_module
      if is_basic_multiqueue
        true # multiqueue_threshold only with basic module multiqueue policies
      elsif policy_opts[:multiqueue_timeout].nil?
        true # No multiqueue_threshold with any other basic module policy than multiqueue*
      end
    elsif policy_opts[:hits].nil? && policy_opts[:multiqueue_timeout].nil?
       true; # No hits/multiqueue_threshold support in the mq module
    else
       false;
    end
  end
end

#--------------------------------

class CacheStack
  include DiskUnits
  include ThinpTestMixin
  include Utils

  attr_accessor :tvm, :md, :ssd, :origin, :cache, :opts

  # options: :cache_size (in sectors), :block_size (in sectors),
  # :policy (class Policy), :format (bool), :origin_size (sectors)


  # FIXME: add methods for changing the policy + args

  def initialize(dm, ssd_dev, spindle_dev, opts)
    @dm = dm
    @ssd_dev = ssd_dev
    @spindle_dev = spindle_dev

    @md = nil
    @ssd = nil
    @origin = nil
    @cache = nil
    @opts = opts

    @tvm = TinyVolumeManager::VM.new
    @tvm.add_allocation_volume(ssd_dev, 0, dev_size(ssd_dev))
    @tvm.add_volume(linear_vol('md', meg(4)))

    cache_size = opts.fetch(:cache_size, gig(1))
    @tvm.add_volume(linear_vol('ssd', cache_size))

    @data_tvm = TinyVolumeManager::VM.new
    @data_tvm.add_allocation_volume(spindle_dev, 0, dev_size(spindle_dev))
    @data_tvm.add_volume(linear_vol('origin', origin_size))
  end

  def activate(&block)
    with_devs(@tvm.table('md'),
              @tvm.table('ssd'),
              @data_tvm.table('origin')) do |md, ssd, origin|
      @md = md
      @ssd = ssd
      @origin = origin

      wipe_device(md, 8) if @opts.fetch(:format, true)

      with_dev(cache_table) do |cache|
        @cache = cache
        block.call(self)
      end
    end
  end

  def resize_ssd(new_size)
    @cache.pause do        # must suspend cache so resize is detected
      @ssd.pause do
        @tvm.resize('ssd', new_size)
        @ssd.load(@tvm.table('ssd'))
      end
    end
  end

  def resize_origin(new_size)
    @opts[:data_size] = new_size

    @cache.pause do
      @origin.pause do
        @data_tvm.resize('origin', new_size)
        @origin.load(@data_tvm.table('origin'))
      end
    end
  end

  def origin_size
    @opts.fetch(:data_size, dev_size(@spindle_dev))
  end

  def metadata_blocks
    @tvm.volumes['md'].length / 8
  end

  def block_size
    @opts.fetch(:block_size, 512)
  end

  def policy_name
    @opts[:policy] = @opts.fetch(:policy, Policy.new('default'))
    @opts[:policy].name
  end

  def policy_opts
    @opts.select { |key, v| @opts[:policy].all_options.include?(key) }
  end

  def io_mode
    @opts[:io_mode] ? [ @opts[:io_mode] ] : []
  end

  def migration_threshold
    @opts[:migration_threshold] ? [ "migration_threshold", opts[:migration_threshold].to_s ] : []
  end

  def cache_table
    Table.new(CacheTarget.new(origin_size, @md, @ssd, @origin,
                              block_size, io_mode + migration_threshold,
                              policy_name, policy_opts))
  end
end

#----------------------------------------------------------------

class CacheTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  extend TestUtils

  POLICY_NAMES = %w(default mq basic multiqueue multiqueue_ws q2 twoqueue
                    fifo lfu mfu lfu_ws mfu_ws lru mru noop random dumb)

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

  def test_dt_cache
    with_standard_cache(:format => true, :data_size => gig(1)) do |cache|
      dt_device(cache)
    end
  end

  def test_dt_linear
    with_standard_linear(:data_size => gig(1)) do |linear|
      dt_device(linear)
    end
  end

  #--------------------------------

  def maxiops(dev, nr_seeks = 10000)
    ProcessControl.run("maxiops -s #{nr_seeks} #{dev} -wb 4096")
  end

  ORION_DIR = './orion_test'

  def orion(dev, fs_type)
    fs = FS::file_system(fs_type, dev)
    fs.format

    Dir.chdir('/root/bin') do
      File.open('orion.lun', 'w+') do |f|
        f.puts dev
      end

      ProcessControl.run("./orion -run simple")
    end
  end

  def discard_dev(dev)
    dev.discard(0, dev_size(dev))
  end

  def test_maxiops_cache_no_discard
    with_standard_cache(:format => true,
                        :data_size => gig(1)) do |cache|
      maxiops(cache, 10000)
    end
  end

  def test_maxiops_cache_with_discard
    size = 512

    with_standard_cache(:format => true,
                        :data_size => gig(1),
                        :cache_size => meg(size)) do |cache|
      discard_dev(cache)
      report_time("maxiops with cache size #{size}m", STDERR) do
        maxiops(cache, 10000)
      end
    end
  end

  def test_maxiops_linear
    with_standard_linear(:data_size => gig(1)) do |linear|
      maxiops(linear, 10000)
    end
  end

  #----------------------------------------------------------------

  def test_dd_cache
    with_standard_cache(:format => true, :data_size => gig(1)) do |cache|
      wipe_device(cache)
    end
  end

  def test_dd_linear
    with_standard_linear(:data_size => gig(1)) do |linear|
      wipe_device(linear)
    end
  end

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

  def do_bonnie(dev, fs_type)
    fs = FS::file_system(fs_type, dev)
    fs.format
    fs.with_mount('./test_fs', :discard => true) do
      Dir.chdir('./test_fs') do
        report_time("bonnie++") do
          ProcessControl::run("bonnie++ -d . -u root -s 1024")
        end
      end
    end
  end

  def do_git_extract_cache_quick(opts)
    i = opts.fetch(:nr_tags, 5)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      git_prepare(stack.cache, :ext4)
      git_extract(stack.cache, :ext4, TAGS[0..i])
    end
  end


  def test_git_extract_cache_quick
    do_git_extract_cache_quick(:policy => Policy.new('mq'),
                               :cache_size => meg(256),
                               :data_size => gig(2))
  end

  def test_orion_cache_simple
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :policy => Policy.new('mq'),
                           :cache_size => meg(256),
                           :data_size => gig(2))
    stack.activate do |stack|
      orion(stack.cache, :ext4)
    end
  end

  def test_orion_linear_simple
    with_standard_linear(:data_size => gig(2)) do |linear|
      orion(linear, :ext4)
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

  #--------------------------------

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

  #--------------------------------

  def test_git_extract_linear
    with_standard_linear do |linear|
      git_prepare(linear, :ext4)
      git_extract(linear, :ext4)
    end
  end

  def test_git_extract_linear_quick
    with_standard_linear(:data_size => gig(2)) do |linear|
      git_prepare(linear, :ext4)
      git_extract(linear, :ext4, TAGS[0..5])
    end
  end

  def test_git_extract_eio_quick
    stack = EnhanceIOStack.new(@dm, @metadata_dev, @data_dev, :cache_size => meg(256))
    stack.activate do |cache|
      git_prepare(cache, :ext4)
      git_extract(cache, :ext4, TAGS[0..5])
    end
  end

  def test_git_extract_bcache_quick
    stack = BcacheStack.new(@dm, @metadata_dev, @data_dev, :cache_size => meg(256))
    stack.activate do |cache|
      git_prepare(cache, :ext4)
      git_extract(cache, :ext4, TAGS[0..5])
    end
  end

  def test_fio_linear
    with_standard_linear do |linear|
      do_fio(linear, :ext4)
    end
  end

  def test_fio_cache
    with_standard_cache(:cache_size => meg(1024),
                        :format => true,
                        :block_size => 512,
                        :data_size => meg(1024),
                        :policy => Policy.new('mq')) do |cache|
      do_fio(cache, :ext4)
    end
  end

  def test_format_linear
    with_standard_linear do |linear|
      do_format(linear, :ext4)
    end
  end

  def test_format_cache
    with_standard_cache(:format => true, :policy => Policy.new('mq')) do |cache|
      do_format(cache, :ext4)
    end
  end

  def test_bonnie_linear
    with_standard_linear do |linear|
      do_bonnie(linear, :ext4)
    end
  end

  def test_bonnie_cache
    with_standard_cache(:cache_size => meg(256),
                        :format => true,
                        :block_size => 512,
                        :policy => Policy.new('mq')) do |cache|
      do_bonnie(cache, :ext4)
    end
  end

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

  def test_dt_cache
    with_standard_cache(:format => true, :policy => Policy.new('mq')) do |cache|
      dt_device(cache)
    end
  end

  def test_unknown_policy_fails
    assert_raise(ExitError) do
      with_standard_cache(:format => true,
                          :policy => Policy.new('time_traveller')) do |cache|
      end
    end
  end

  def wait_for_all_clean(cache)
    cache.event_tracker.wait(cache) do |cache|
      status = CacheStatus.new(cache)
      STDERR.puts "#{status.nr_dirty} dirty blocks"
      status.nr_dirty == 0
    end
  end

  def test_cleaner_policy
    with_standard_cache(:format => true) do |cache|
      git_prepare(cache, :ext4)

      cache.pause do
        table = cache.active_table
        table.targets[0].args[5] = 'cleaner'
        cache.load(table)
      end

      wait_for_all_clean(cache)
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

  def test_writethrough
    size = gig(2)

    # wipe the origin to ensure we don't accidentally have the same
    # data on it.
    with_standard_linear(:data_size => size) do |origin|
      wipe_device(origin)
    end

    # format and set up a git repo on the cache
    with_standard_cache(:format => true,
                        :io_mode => :writethrough,
                        :data_size => size) do |cache|
      git_prepare(cache, :ext4)
    end

    # origin should have all data
    with_standard_linear(:data_size => size) do |origin|
      git_extract(origin, :ext4, TAGS[0..1])
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


  ##############################################################################
  #
  # ctr/message/status/table interface tests
  #
  # Check for defaults, set alternates and check those got set properly.
  #
  def get_opt(opts, o)
    for i in 1..9
      oo = (o.to_s + "_#{i}").to_sym
      return opts[oo] if opts[oo]
    end

    nil
  end

  def dev_to_hex(dm_dev)
    begin
      rdev = (f = File.open(dm_dev.path)).stat.rdev
      major = rdev / 256
      major.to_s + ':' + (rdev - major * 256).to_s
    ensure
      f.close unless f.nil?
    end
  end

  def ctr_message_status_interface(opts, msg = nil)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      cache = stack.cache
      cache.message(msg) if msg
      [ CacheTable.new(cache), CacheStatus.new(cache),
        stack.origin_size, stack.block_size, stack.metadata_blocks,
        dev_to_hex(stack.md), dev_to_hex(stack.ssd), dev_to_hex(stack.origin) ]
    end
  end

  # Check ctr cache stack with optional massages to set io thresholds etc.
  def do_ctr_message_status_interface(do_msg, opts = Hash.new)
    policy = opts.fetch(:policy, Policy.new('basic'))
    msg = nil
    defaults = {
      :io_mode => 'writeback',
      :migration_threshold => 2048 * 100,
      :sequential_threshold => 512,
      :random_threshold => 4,
      :multiqueue_timeout => 5000,
      :hits => 0
    }
    expected = Hash.new

    defaults.each_pair do |o, val|
      if do_msg
        v = get_opt(opts, o)
        expected[o] = v ? v : opts.fetch(o, val)

        # delete the message option to avoid it as a ctr key pair
        msg = [ '0 set_config', o.to_s, opts.delete(o).to_s ].join(' ') if opts[o]
      else
        v = get_opt(policy.opts, o)
        expected[o] = v ? v : policy.opts.fetch(o, val)
      end
    end

    # Got to invert hits option for expected check further down
    expected[:hits] = expected[:hits] == 0 ? 1 : 0 if opts[:hits] || policy.opts[:hits]
    table, status, origin_size, block_size, md_total = ctr_message_status_interface(opts, msg)
    nr_blocks = origin_size / block_size

    # sequential/random/migration threshold assertions
    assert(status.policy_args[0] == expected[:sequential_threshold])
    assert(status.policy_args[1] == expected[:random_threshold])
    assert(status.migration_threshold == expected[:migration_threshold])

    # allocation/demotion/promotion assertions
    assert(status.md_used != 0)
    assert(status.demotions == 0)
    assert(status.md_total == md_total)
    assert(status.promotions <= nr_blocks)
    assert(status.promotions == status.residency)

    if policy.is_basic_module
      # Default multiqueue timeout paying attention to rounding divergence caused by the basic modules timout calculation
      assert((status.policy_args[2] - expected[:multiqueue_timeout]).abs < 10) if policy.is_basic_multiqueue

      # T_HITS/T_SECTORS accounting
      assert(status.policy_args[3] == expected[:hits])
    end
  end

  def status_defaults(policy_name)
    do_ctr_message_status_interface(false, :policy => Policy.new(policy_name))
  end

  define_tests_across(:status_defaults, POLICY_NAMES)

  #--------------------------------
  # Tests policy modules setting of sequential/random thresholds
  def message_thresholds(name = 'basic')
    with_policy(name) { |policy| do_ctr_message_status_interface(true, :policy => policy, :sequential_threshold => 768) }
    with_policy(name) { |policy| do_ctr_message_status_interface(true, :policy => policy, :random_threshold => 44) }
  end

  define_tests_across(:message_thresholds, POLICY_NAMES)

  #--------------------------------
  # Test change of target migration threshold
  def test_message_target_migration_threshold
    do_ctr_message_status_interface(true, :policy => Policy.new('basic'), :migration_threshold => 2000 * 100)
  end

  #--------------------------------
  # Test policy replacement module ctr arguments
  def with_policy(name, opts = Hash.new, &block)
    block.call(Policy.new(name, opts))
  end

  def ctr_tests(name = 'basic')
    TestCases.new.params.each do |should_fail, feature_opts, policy_opts|
      with_policy(name, policy_opts) do |policy|
        if policy.run_test
          policy_opts[:policy] = policy;

          if feature_opts.size > 0
            should_fail = true
            policy_opts.merge!(feature_opts)
          end

          if should_fail
            assert_raise(ExitError) do
              do_ctr_message_status_interface(false, policy_opts)
            end
          else
            do_ctr_message_status_interface(false, policy_opts)
          end
        end
      end
    end
  end

  define_tests_across(:ctr_tests, POLICY_NAMES)

  #--------------------------------
  # No target ctr migration_threshold key pair as yet....
  def test_ctr_migration_threshold_fails
    assert_raise(ExitError) do
      do_ctr_message_status_interface(false, :policy => Policy.new('basic'), :migration_threshold => 2000 * 100)
    end
  end


  #------------------------------------------------
  #
  # Cache table correctness tests
  #
  def is_valid_feature_arg(name)
    ['writeback', 'writethrough'].include?(name)
  end

  def do_table_check_test(opts = Hash.new)
    table, status, origin_size, block_size, md_total, metadata_dev, cache_dev, origin_dev = ctr_message_status_interface(opts)

    assert(table.metadata_dev == metadata_dev)
    assert(table.cache_dev == cache_dev)
    assert(table.origin_dev == origin_dev)
    assert(table.block_size == block_size)
    assert(table.nr_feature_args == table.feature_args.length)
    table.feature_args.each { |arg| assert(is_valid_feature_arg(arg)) }
    assert(opts[:policy].is_valid_policy_name(table.policy_name))
    assert(table.nr_policy_args == table.policy_args.length)
    table.policy_args.each { |arg| assert(opts[:policy].is_valid_policy_arg(arg)) if arg[0] == /w/ }
  end

  def table_check(name = 'basic')
    TestCases.new.params.each do |should_fail, feature_opts, policy_opts|
      with_policy(name, policy_opts) do |policy|
        if policy.run_test
          feature_opts[:policy] = policy;
          if should_fail
            assert_raise(ExitError) do
              do_table_check_test(feature_opts)
            end
          else
            do_table_check_test(feature_opts)
          end
        end
      end
    end
  end

  define_tests_across(:table_check, POLICY_NAMES)

  def test_status
    opts = Hash.new
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      status = CacheStatus.new(stack.cache)

      assert(status.core_args.assoc('migration_threshold'), '12345')
      assert(status.policy_args.assoc('random_threshold'), '4321')
    end
  end

  def test_table
    opts = Hash.new
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      assert(stack.cache.table =~ /0 41943040 cache \d+:\d+ \d+:\d+ \d+:\d+ 512 0 default 0/)
    end
  end

  def test_message
    opts = Hash.new
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      stack.cache.message(0, "migration_threshold 12345")
      stack.cache.message(0, "random_threshold 4321")
      status = CacheStatus.new(stack.cache)

      assert(status.core_args.assoc('migration_threshold'), '12345')
      assert(status.policy_args.assoc('random_threshold'), '4321')
    end
  end
end

#----------------------------------------------------------------
