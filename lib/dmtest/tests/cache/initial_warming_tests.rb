require 'dmtest/blktrace'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/cache_policy'

require 'rspec/expectations'

#----------------------------------------------------------------

class InitialWarmingTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  include CacheUtils
  extend TestUtils
  include BlkTrace

  def setup
    super
    @data_block_size = meg(1)
    @cache_blocks = 1024
  end

  #--------------------------------

  def git_extract_with_tunables(desc, tunables = Hash.new)
    with_standard_linear(:data_size => gig(2)) do |linear|
      git_prepare(linear, :ext4)
    end

    tunables[:migration_threshold] = gig(1)
    s = make_stack(:format => true,
                   :data_size => gig(2),
                   :block_size => @data_block_size,
                   :cache_size => @data_block_size * @cache_blocks,
                   :io_mode => :writeback,
                   :policy => Policy.new('mq', tunables))
    s.activate do
      report_time("git extract, #{desc}", STDERR) do
        git_extract(s.cache, :ext4, TAGS[0..5])
      end
    end
  end

  def test_tunables_10
    git_extract_with_tunables("tunables = 10",
                              :migration_threshold => gig(1),
                              :read_promote_adjustment => 10,
                              :write_promote_adjustment => 10)
  end

  def test_tunables_0
    git_extract_with_tunables("tunables = 0", 
                              :migration_threshold => gig(1),
                              :read_promote_adjustment => 0,
                              :write_promote_adjustment => 0)
  end
end

#----------------------------------------------------------------
