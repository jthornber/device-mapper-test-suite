#----------------------------------------------------------------

class Policy
  attr_accessor :name, :opts

  def initialize(name, opts = Hash.new)
    @name = name
    @opts = opts
  end
end

class CheckedPolicy < Policy
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

#----------------------------------------------------------------
