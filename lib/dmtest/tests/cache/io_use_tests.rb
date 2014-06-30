require 'dmtest/blktrace'
require 'dmtest/cache-status'
require 'dmtest/cache_policy'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/disk-units'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/tags'
require 'dmtest/test-utils'
require 'dmtest/thinp-test'
require 'dmtest/tvm.rb'
require 'dmtest/utils'

require 'rspec/expectations'

#----------------------------------------------------------------

class IOUseTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include BlkTrace
  include DiskUnits
  include CacheUtils
  extend TestUtils

  def test_no_io_when_idle
    s = CacheStack.new(@dm, @metadata_dev, @data_dev,
                       :data_size => gig(2),
                       :block_size => k(64),
                       :cache_size => gig(1),
                       :io_mode => :writethrough,
                       :policy => Policy.new('mq'))
    s.activate do
      # Warm the cache dev up
      git_prepare(s.cache, :ext4)
      git_extract(s.cache, :ext4, TAGS[0..5])

      sleep 10

      traces, _ = blktrace(@metadata_dev, @data_dev) do
        sleep 30
      end

      STDERR.puts "traces: #{traces}"
      assert(traces[0].empty?)
      assert(traces[1].empty?)
    end
  end
end

#----------------------------------------------------------------
