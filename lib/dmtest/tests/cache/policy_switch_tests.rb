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

class PolicySwitchTests < ThinpTestCase
  include GitExtract
  include Utils
  include DiskUnits
  extend TestUtils

  def with_standard_stack(opts = Hash.new, &block)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate(&block)
  end

  def switch_policy(stack, policy_name)
    stack.cache.pause do
      stack.change_policy(Policy.new(policy_name))
      stack.cache.load(stack.cache_table)
    end
  end

  # bz1269959
  # Starting with the cleaner policy knocks it over.  Starting with
  # another policy and then switching to cleaner appears to be safe.
  define_test :switch_through_the_policies do
    with_standard_stack(:cache_size => gig(4),
                        :format => true,
                        :block_size => 128,
                        :data_size => gig(4),
                        :io_mode => :writeback,
                        :policy => Policy.new('cleaner')) do |stack|
      switch_policy(stack, 'smq')
      switch_policy(stack, 'mq')
    end
  end
end

#----------------------------------------------------------------
