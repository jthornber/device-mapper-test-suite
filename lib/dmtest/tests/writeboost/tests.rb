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

require 'dmtest/tests/writeboost/stack'

require 'pp'

#----------------------------------------------------------------

class WriteboostTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  include FioSubVolumeScenario
  extend TestUtils

  def test_fio_sub_volume
    s = WriteboostStack.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      s.cleanup_cache
      wait = lambda {sleep(5)}
      fio_sub_volume_scenario(s.wb, &wait)
    end
  end

  def test_fio_cache
    s = WriteboostStack.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      s.cleanup_cache
      do_fio(s.wb, :ext4)
    end
  end

  def test_fio_database_funtime
    s = WriteboostStack.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      s.cleanup_cache
      do_fio(s.wb, :ext4,
             :outfile => AP("fio_writeboost.out"),
             :cfgfile => LP("tests/cache/database-funtime.fio"))
    end
  end
end

#----------------------------------------------------------------
