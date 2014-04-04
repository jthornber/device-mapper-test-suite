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

  attr_accessor :stack_maker

  def test_fio_sub_volume
    return unless @stack_maker
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      s.cleanup_cache
      wait = lambda {sleep(5)}
      fio_sub_volume_scenario(s.wb, &wait)
    end
  end

  def test_fio_cache
    return unless @stack_maker
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      s.cleanup_cache
      do_fio(s.wb, :ext4)
    end
  end

  def test_fio_database_funtime
    return unless @stack_maker
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      s.cleanup_cache
      do_fio(s.wb, :ext4,
             :outfile => AP("fio_writeboost.out"),
             :cfgfile => LP("tests/cache/database-funtime.fio"))
    end
  end

  def build_and_test_ruby
    ProcessControl.run("./configure")
    ProcessControl.run("make -j")
    ProcessControl.run("echo 3 > /proc/sys/vm/drop_caches")
    ProcessControl.run("make test")
  end

  # make & make test a ruby interpreter
  def test_ruby_compile
    s = WriteboostStack.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      ruby = "ruby-2.1.1"

      fs = FS::file_system(:xfs, s.wb)
      fs.format

      mount_dir = "./ruby_mount_1"
      fs.with_mount(mount_dir) do
        pn = LP("tests/writeboost/#{ruby}.tar.gz")
        ProcessControl.run("cp #{pn} #{mount_dir}")
        Dir.chdir(mount_dir) do
          ProcessControl.run("tar xvfz #{ruby}.tar.gz")
          Dir.chdir(ruby) do
            build_and_test_ruby
          end
        end
      end
    end
  end
end

class WriteboostTestsType0 < WriteboostTests
  def setup
    super
    @stack_maker = WriteboostStackType0
  end
end

class WriteboostTestsType1 < WriteboostTests
  def setup
    super
    @stack_maker = WriteboostStackType1
  end
end
#----------------------------------------------------------------
