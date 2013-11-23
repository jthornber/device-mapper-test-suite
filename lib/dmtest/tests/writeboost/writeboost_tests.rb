require 'dmtest/config'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tests/cache/fio_subvolume_scenario'
require 'dmtest/tests/writeboost/writeboost_stack'

require 'pp'

#----------------------------------------------------------------

class WriteboostTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  include FioSubVolumeScenario
  extend TestUtils

  def with_standard_cache(opts = Hash.new, &block)
    stack = WriteboostStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      block.call(stack.cache)
    end
  end

  def test_fio_sub_volume
    with_standard_cache(:cache_size => meg(256),
                        :format => true,
                        :data_size => gig(4)) do |cache|
      wait = lambda {sleep(5)}
      fio_sub_volume_scenario(cache, &wait)
    end
  end

  def test_fio_cache
    with_standard_cache(:cache_size => meg(512),
                        :format => true,
                        :data_size => gig(2)) do |cache|
      do_fio(cache, :ext4)
    end
  end

  def test_fio_database_funtime
    with_standard_cache(:cache_size => meg(1024),
                        :format => true,
                        :data_size => gig(10)) do |cache|
      do_fio(cache, :ext4,
             :outfile => AP("fio_writeboost.out"),
             :cfgfile => LP("tests/cache/database-funtime.fio"))
    end
  end
end

#----------------------------------------------------------------
