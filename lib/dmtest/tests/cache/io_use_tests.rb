require 'dmtest/blktrace'
require 'dmtest/cache-status'
require 'dmtest/cache_policy'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/disk-units'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/test-utils'
require 'dmtest/thinp-test'
require 'dmtest/tvm.rb'
require 'dmtest/utils'

require 'rspec/expectations'

#----------------------------------------------------------------

class IOUseTests < ThinpTestCase
  include GitExtract
  include Utils
  include BlkTrace
  include DiskUnits
  include CacheUtils
  extend TestUtils

  POLICY_NAMES = %w(mq smq)
  IO_MODES = [:writethrough, :writeback]

  def no_io_when_idle(policy, io_mode)
    s = CacheStack.new(@dm, @metadata_dev, @data_dev,
                       :data_size => gig(2),
                       :block_size => k(64),
                       :cache_size => gig(1),
                       :io_mode => io_mode,
                       :policy => Policy.new(policy))
    s.activate_support_devs do
      s.prepare_populated_cache(:dirty_percentage => 0)
      s.activate_top_level do
        sleep 10                # give udev time to examine the devs

        STDERR.puts "beginning idle period"
        traces, _ = blktrace(@metadata_dev, @data_dev) do
          sleep 30
        end
        STDERR.puts "done"

        assert(traces[0].empty?)
        assert(traces[1].empty?)
      end
    end
  end

  define_tests_across(:no_io_when_idle, POLICY_NAMES, IO_MODES)
end

#----------------------------------------------------------------
