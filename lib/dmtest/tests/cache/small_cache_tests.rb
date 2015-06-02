require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/pool-stack'
require 'dmtest/tags'
require 'dmtest/test-utils'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/cache_policy'
require 'dmtest/thinp-test'
require 'dmtest/tvm.rb'
require 'dmtest/utils'

require 'rspec/expectations'

#----------------------------------------------------------------

class SmallConfigTests < ThinpTestCase
  include Tags
  include Utils
  include DiskUnits
  include DMThinUtils
  include CacheUtils
  extend TestUtils

  POLICY_NAMES = %w(mq smq)

  def setup
    super
    @data_block_size = k(32)
    @cache_blocks = 1024
  end

  #--------------------------------

  def small_stack(policy)
    s = make_stack(:format => true,
                   :metadata_size => meg(8),
                   :block_size => k(32),
                   :cache_size => k(50),
                   :data_size => k(50))
    s.activate do
      wipe_device(s.cache)
    end
  end

  define_tests_across(:small_stack, POLICY_NAMES)
end

#----------------------------------------------------------------
