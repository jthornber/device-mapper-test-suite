# FIXME: move to a separate file

POLICY_NAMES = %w(default mq basic multiqueue multiqueue_ws q2 twoqueue
                  fifo lfu mfu lfu_ws mfu_ws lru mru noop random dumb)


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

#--------------------------------


#--------------------------------

class CacheCtrTests < ThinpTestCase

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
end

#----------------------------------------------------------------
